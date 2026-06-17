from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parents[1]
BLOCKED_HOSTS = {"localhost", "127.0.0.1", "10.0.2.2", "your-backend.example.com"}

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")


@dataclass(frozen=True)
class Check:
    name: str
    status: str
    detail: str


def load_json(path: Path) -> tuple[dict | None, str | None]:
    if not path.exists():
        return None, "missing"
    try:
        return json.loads(path.read_text(encoding="utf-8-sig")), None
    except Exception as exc:  # noqa: BLE001 - evidence parser reports any malformed file.
        return None, f"invalid JSON: {exc}"


def has_nonempty_file(path: Path) -> bool:
    try:
        return path.exists() and path.is_file() and path.stat().st_size > 0
    except OSError:
        return False


def mobile_pubspec_version() -> tuple[str, str]:
    pubspec = ROOT / "mobile" / "pubspec.yaml"
    if not pubspec.exists():
        return "", ""
    for line in pubspec.read_text(encoding="utf-8").splitlines():
        match = re.match(r"^version:\s*(\S+)\s*$", line)
        if match:
            full = match.group(1).strip()
            return full, full.split("+", 1)[0]
    return "", ""


def parse_iso_datetime(value: object) -> datetime | None:
    if not isinstance(value, str) or not value.strip():
        return None
    text = value.strip()
    if text.endswith("Z"):
        text = f"{text[:-1]}+00:00"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def is_install_ready_url(url: str, *, allow_local: bool = False) -> bool:
    parsed = urlparse(url)
    if allow_local and parsed.scheme in {"http", "https"} and parsed.hostname in {"localhost", "127.0.0.1", "10.0.2.2"}:
        return True
    return parsed.scheme == "https" and parsed.hostname not in BLOCKED_HOSTS


def normalize_url(url: str) -> str:
    parsed = urlparse(url.strip())
    if not parsed.scheme or not parsed.netloc:
        return url.strip().rstrip("/")
    scheme = parsed.scheme.lower()
    host = (parsed.hostname or "").lower()
    port = parsed.port
    default_port = (scheme == "http" and port == 80) or (scheme == "https" and port == 443)
    netloc = host if port is None or default_port else f"{host}:{port}"
    path = parsed.path.rstrip("/")
    return f"{scheme}://{netloc}{path}"


def check_deployment(path: Path, *, allow_local_urls: bool = False) -> list[Check]:
    data, error = load_json(path)
    if error == "missing":
        return [Check("deployment", "pending", f"{path} not found")]
    if error:
        return [Check("deployment", "fail", f"{path}: {error}")]

    checks: list[Check] = []
    base_url = str(data.get("base_url", ""))
    if is_install_ready_url(base_url, allow_local=allow_local_urls):
        checks.append(Check("deployment_url", "pass", base_url))
    else:
        checks.append(Check("deployment_url", "fail", f"not an install-ready HTTPS URL: {base_url!r}"))

    health = data.get("health") if isinstance(data.get("health"), dict) else {}
    checks.append(
        Check(
            "deployment_health",
            "pass" if health.get("status") == "ok" else "fail",
            f"health.status={health.get('status')!r}",
        )
    )
    checks.append(
        Check(
            "deployment_smoke",
            "pass" if data.get("smoke_passed") is True else "fail",
            f"smoke_passed={data.get('smoke_passed')!r}",
        )
    )
    checks.append(
        Check(
            "deployment_device_config",
            "pass" if data.get("device_config_checked") is True else "fail",
            f"device_config_checked={data.get('device_config_checked')!r}",
        )
    )
    volume_persistence = data.get("volume_persistence")
    if (
        data.get("volume_persistence_checked") is True
        and isinstance(volume_persistence, dict)
        and volume_persistence.get("db_marker_checked") is True
        and volume_persistence.get("file_marker_checked") is True
    ):
        checks.append(Check("zeabur_volume_persistence", "pass", "DB and file markers survived restart"))
        source_path = Path(str(volume_persistence.get("source_evidence") or ""))
        source_data, source_error = load_json(source_path)
        if source_error:
            checks.append(Check("zeabur_volume_source_evidence", "fail", f"{source_path}: {source_error}"))
            checks.append(Check("zeabur_volume_marker_match", "fail", "source evidence is missing or invalid"))
        else:
            previous_marker = source_data.get("volume_persistence_marker") if isinstance(source_data, dict) else {}
            marker_device_id = str(volume_persistence.get("marker_device_id") or "")
            file_url = str(volume_persistence.get("file_url") or "")
            previous_device_id = str(previous_marker.get("device_id") or "") if isinstance(previous_marker, dict) else ""
            previous_file_url = str(previous_marker.get("file_url") or "") if isinstance(previous_marker, dict) else ""
            checks.append(Check("zeabur_volume_source_evidence", "pass", str(source_path)))
            checks.append(
                Check(
                    "zeabur_volume_marker_match",
                    "pass" if marker_device_id == previous_device_id and file_url == previous_file_url else "fail",
                    f"current=({marker_device_id}, {file_url}), source=({previous_device_id}, {previous_file_url})",
                )
            )
    else:
        checks.append(
            Check(
                "zeabur_volume_persistence",
                "pending",
                "add evidence after a Zeabur service restart confirms DB/files still exist",
            )
        )
    return checks


def check_cross_evidence_consistency(deployment_path: Path, uptime_path: Path, android_install_path: Path) -> list[Check]:
    deployment, deployment_error = load_json(deployment_path)
    if deployment_error:
        return []

    deployment_url = normalize_url(str(deployment.get("base_url", "")))
    if not deployment_url:
        return []

    checks: list[Check] = []
    uptime, uptime_error = load_json(uptime_path)
    if not uptime_error:
        uptime_url = normalize_url(str(uptime.get("base_url", "")))
        checks.append(
            Check(
                "deployment_uptime_url_match",
                "pass" if uptime_url == deployment_url else "fail",
                f"deployment={deployment_url}, uptime={uptime_url or 'missing'}",
            )
        )

    android, android_error = load_json(android_install_path)
    if not android_error:
        manifest = android.get("manifest") if isinstance(android.get("manifest"), dict) else {}
        android_url = normalize_url(str(manifest.get("backend_url", "")))
        checks.append(
            Check(
                "deployment_android_url_match",
                "pass" if android_url == deployment_url else "fail",
                f"deployment={deployment_url}, android={android_url or 'missing'}",
            )
        )

    return checks


def check_android_install(path: Path, *, allow_local_urls: bool = False) -> list[Check]:
    data, error = load_json(path)
    if error == "missing":
        return [Check("android_install", "pending", f"{path} not found")]
    if error:
        return [Check("android_install", "fail", f"{path}: {error}")]

    checks: list[Check] = []
    manifest = data.get("manifest") if isinstance(data.get("manifest"), dict) else {}
    backend_url = str(manifest.get("backend_url", ""))
    checks.append(
        Check(
            "android_backend_url",
            "pass" if is_install_ready_url(backend_url, allow_local=allow_local_urls) else "fail",
            backend_url or "missing backend_url",
        )
    )
    checks.append(
        Check(
            "android_placeholder_flag",
            "pass" if manifest.get("placeholder_allowed") is False else "fail",
            f"placeholder_allowed={manifest.get('placeholder_allowed')!r}",
        )
    )
    checks.append(
        Check(
            "android_release_signing",
            "pass" if manifest.get("signing") == "dedicated release keystore" else "fail",
            f"signing={manifest.get('signing')!r}",
        )
    )
    package_name = str(data.get("package") or "")
    manifest_package = str(manifest.get("package") or "")
    checks.append(
        Check(
            "android_package_consistency",
            "pass" if package_name and package_name == manifest_package else "fail",
            f"installed={package_name or 'missing'}, manifest={manifest_package or 'missing'}",
        )
    )
    checks.append(
        Check(
            "android_sha256",
            "pass" if isinstance(data.get("sha256"), str) and len(data["sha256"]) == 64 else "fail",
            str(data.get("sha256")),
        )
    )
    manifest_sha = str(manifest.get("sha256") or "")
    if data.get("sha256"):
        checks.append(
            Check(
                "android_manifest_sha256_consistency",
                "pass" if manifest_sha == data.get("sha256") else "fail",
                f"manifest={manifest_sha or 'missing'}, install={data.get('sha256')}",
            )
        )
    checks.append(
        Check(
            "android_apk_size",
            "pass" if int(data.get("apk_bytes") or 0) > 0 else "fail",
            f"apk_bytes={data.get('apk_bytes')!r}",
        )
    )
    manifest_apk_bytes = int(manifest.get("apk_bytes") or 0)
    install_apk_bytes = int(data.get("apk_bytes") or 0)
    checks.append(
        Check(
            "android_manifest_apk_size_consistency",
            "pass" if manifest_apk_bytes > 0 and manifest_apk_bytes == install_apk_bytes else "fail",
            f"manifest={manifest_apk_bytes}, install={install_apk_bytes}",
        )
    )
    device = data.get("device") if isinstance(data.get("device"), dict) else {}
    model = " ".join(
        part for part in [str(device.get("manufacturer", "")).strip(), str(device.get("model", "")).strip()] if part
    )
    checks.append(
        Check(
            "android_device_model",
            "pass" if model else "pending",
            model or "install evidence should include manufacturer/model",
        )
    )
    expected_full_version, expected_version_name = mobile_pubspec_version()
    manifest_version = str(manifest.get("version") or "")
    if expected_full_version:
        checks.append(
            Check(
                "android_manifest_version",
                "pass" if manifest_version == expected_full_version else "fail",
                f"manifest={manifest_version or 'missing'}, expected={expected_full_version}",
            )
        )
    else:
        checks.append(Check("android_manifest_version", "pending", "mobile/pubspec.yaml version not found"))

    installed_version_name = str(data.get("installed_version_name") or "")
    checks.append(
        Check(
            "android_installed_version",
            "pass" if expected_version_name and installed_version_name == expected_version_name else "pending" if not installed_version_name else "fail",
            f"installed={installed_version_name or 'missing'}, expected={expected_version_name or 'unknown'}",
        )
    )
    checks.append(
        Check(
            "android_launch_checked",
            "pass" if data.get("launch_checked") is True else "pending",
            f"launch_checked={data.get('launch_checked')!r}",
        )
    )
    screenshot_path = data.get("screenshot_path")
    if screenshot_path:
        screenshot = Path(str(screenshot_path))
        checks.append(
            Check(
                "android_launch_screenshot",
                "pass" if has_nonempty_file(screenshot) else "pending",
                f"{screenshot} ({screenshot.stat().st_size} bytes)" if has_nonempty_file(screenshot) else str(screenshot),
            )
        )
    else:
        checks.append(Check("android_launch_screenshot", "pending", "install evidence should include launch screenshot_path"))
    verification = data.get("verification") if isinstance(data.get("verification"), dict) else {}
    signature = verification.get("signature") if isinstance(verification.get("signature"), dict) else {}
    verification_sha = verification.get("sha256")
    verification_apk_bytes = int(verification.get("apk_bytes") or 0) if verification else 0
    checks.append(
        Check(
            "android_verify_evidence",
            "pass" if verification else "fail",
            "verification evidence embedded" if verification else "install evidence must include .verify.json contents",
        )
    )
    checks.append(
        Check(
            "android_verify_sha256",
            "pass" if verification_sha == data.get("sha256") else "fail",
            f"verify_sha256={verification_sha!r}",
        )
    )
    checks.append(
        Check(
            "android_verify_apk_size",
            "pass" if verification_apk_bytes > 0 and verification_apk_bytes == install_apk_bytes else "fail",
            f"verify={verification_apk_bytes}, install={install_apk_bytes}",
        )
    )
    checks.append(
        Check(
            "android_apksigner_checked",
            "pass" if signature.get("checked") is True else "fail",
            f"checked={signature.get('checked')!r}",
        )
    )
    checks.append(
        Check(
            "android_signature_scheme",
            "pass" if (signature.get("v2") or signature.get("v3") or signature.get("v31")) else "fail",
            f"v2={signature.get('v2')!r}, v3={signature.get('v3')!r}, v3.1={signature.get('v31')!r}",
        )
    )
    return checks


def check_ios_install(path: Path) -> list[Check]:
    data, error = load_json(path)
    if error == "missing":
        return [Check("ios_install", "pending", f"{path} not found")]
    if error:
        return [Check("ios_install", "fail", f"{path}: {error}")]

    checks: list[Check] = []
    platform = str(data.get("platform", "")).lower()
    checks.append(
        Check(
            "ios_platform",
            "pass" if platform == "ios" else "fail",
            f"platform={data.get('platform')!r}",
        )
    )
    checks.append(
        Check(
            "ios_device_model",
            "pass" if str(data.get("device_model", "")).strip() else "fail",
            str(data.get("device_model") or "missing device_model"),
        )
    )
    checks.append(
        Check(
            "ios_version",
            "pass" if str(data.get("ios_version", "")).strip() else "fail",
            str(data.get("ios_version") or "missing ios_version"),
        )
    )
    checks.append(
        Check(
            "ios_app_version",
            "pass" if str(data.get("app_version", "")).strip() else "fail",
            str(data.get("app_version") or "missing app_version"),
        )
    )
    expected_full_version, _ = mobile_pubspec_version()
    if expected_full_version and str(data.get("app_version", "")).strip():
        app_version = str(data.get("app_version", "")).strip()
        checks.append(
            Check(
                "ios_app_version_matches_pubspec",
                "pass" if app_version == expected_full_version else "fail",
                f"ios={app_version}, expected={expected_full_version}",
            )
        )
    elif not expected_full_version:
        checks.append(Check("ios_app_version_matches_pubspec", "pending", "mobile/pubspec.yaml version not found"))
    bundle_id = str(data.get("bundle_id", ""))
    checks.append(
        Check(
            "ios_bundle_id",
            "pass" if bundle_id.startswith("com.family.photorescue.") else "fail",
            bundle_id or "missing bundle_id",
        )
    )
    build_method = str(data.get("build_method", "")).strip()
    checks.append(
        Check(
            "ios_build_method",
            "pass" if build_method else "fail",
            build_method or "missing build_method",
        )
    )
    screenshot_path = data.get("screenshot_path")
    if screenshot_path:
        screenshot = Path(str(screenshot_path))
        checks.append(
            Check(
                "ios_screenshot",
                "pass" if has_nonempty_file(screenshot) else "pending",
                f"{screenshot} ({screenshot.stat().st_size} bytes)" if has_nonempty_file(screenshot) else str(screenshot),
            )
        )
    else:
        checks.append(Check("ios_screenshot", "pending", "optional screenshot_path not recorded"))
    return checks


def check_uptime(
    path: Path,
    min_hours: float,
    max_failure_rate_percent: float,
    *,
    allow_local_urls: bool = False,
) -> list[Check]:
    data, error = load_json(path)
    if error == "missing":
        return [Check("uptime_monitor", "pending", f"{path} not found")]
    if error:
        return [Check("uptime_monitor", "fail", f"{path}: {error}")]

    checks: list[Check] = []
    base_url = str(data.get("base_url", ""))
    checks.append(
        Check(
            "uptime_url",
            "pass" if is_install_ready_url(base_url, allow_local=allow_local_urls) else "fail",
            base_url or "missing base_url",
        )
    )
    duration_hours = float(data.get("duration_seconds") or 0) / 3600
    checks.append(
        Check(
            "uptime_duration",
            "pass" if duration_hours >= min_hours else "pending",
            f"{duration_hours:.2f}/{min_hours:.2f} hours",
        )
    )
    started_at = parse_iso_datetime(data.get("started_at"))
    ended_at = parse_iso_datetime(data.get("ended_at"))
    if started_at and ended_at and ended_at >= started_at:
        wall_duration_seconds = (ended_at - started_at).total_seconds()
        reported_duration_seconds = float(data.get("duration_seconds") or 0)
        tolerance_seconds = max(5.0, float(data.get("interval_seconds") or 0) + 5.0)
        duration_delta = abs(wall_duration_seconds - reported_duration_seconds)
        checks.append(
            Check(
                "uptime_wall_clock_duration",
                "pass" if wall_duration_seconds / 3600 >= min_hours else "pending",
                f"{wall_duration_seconds / 3600:.2f}/{min_hours:.2f} hours from started_at/ended_at",
            )
        )
        checks.append(
            Check(
                "uptime_duration_consistency",
                "pass" if duration_delta <= tolerance_seconds else "fail",
                f"reported={reported_duration_seconds:.2f}s, wall={wall_duration_seconds:.2f}s",
            )
        )
    else:
        checks.append(Check("uptime_wall_clock_duration", "pending", "started_at/ended_at missing or invalid"))
        checks.append(Check("uptime_duration_consistency", "pending", "started_at/ended_at missing or invalid"))

    sample_count = int(data.get("sample_count") or 0)
    samples = data.get("samples") if isinstance(data.get("samples"), list) else []
    checks.append(
        Check(
            "uptime_samples",
            "pass" if sample_count > 0 else "fail",
            f"sample_count={sample_count}",
        )
    )
    checks.append(
        Check(
            "uptime_sample_count_consistency",
            "pass" if len(samples) == sample_count else "fail",
            f"samples={len(samples)}, sample_count={sample_count}",
        )
    )
    interval_seconds = float(data.get("interval_seconds") or 0)
    if interval_seconds > 0 and float(data.get("duration_seconds") or 0) > 0:
        expected_min_samples = max(1, int(float(data.get("duration_seconds") or 0) / interval_seconds) - 1)
        checks.append(
            Check(
                "uptime_sample_density",
                "pass" if sample_count >= expected_min_samples else "fail",
                f"{sample_count}/{expected_min_samples} samples for interval {interval_seconds:.0f}s",
            )
        )
    else:
        checks.append(Check("uptime_sample_density", "pending", "interval_seconds or duration_seconds missing"))

    failure_rate = float(data.get("failure_rate_percent") or 0)
    computed_failures = sum(1 for sample in samples if isinstance(sample, dict) and sample.get("ok") is not True)
    failure_count = int(data.get("failure_count") or 0)
    computed_failure_rate = 100.0 if sample_count <= 0 else round((computed_failures / sample_count) * 100, 3)
    checks.append(
        Check(
            "uptime_failure_rate",
            "pass" if failure_rate <= max_failure_rate_percent else "fail",
            f"{failure_rate:.3f}% <= {max_failure_rate_percent:.3f}%",
        )
    )
    checks.append(
        Check(
            "uptime_failure_count_consistency",
            "pass" if computed_failures == failure_count else "fail",
            f"reported={failure_count}, samples={computed_failures}",
        )
    )
    checks.append(
        Check(
            "uptime_failure_rate_consistency",
            "pass" if abs(computed_failure_rate - failure_rate) <= 0.001 else "fail",
            f"reported={failure_rate:.3f}%, samples={computed_failure_rate:.3f}%",
        )
    )
    checks.append(
        Check(
            "uptime_monitor_passed",
            "pass" if data.get("monitor_passed") is True else "fail",
            f"monitor_passed={data.get('monitor_passed')!r}",
        )
    )
    return checks


def feedback_records(path: Path) -> list[str]:
    if not path.exists():
        return []
    text = path.read_text(encoding="utf-8")
    entries = re.split(r"(?m)^###\s+", text)
    return [entry.strip() for entry in entries[1:] if "日期:" in entry or "使用人:" in entry]


def field_value(record: str, field: str) -> str:
    match = re.search(rf"(?m)^{re.escape(field)}:\s*(.*)$", record)
    return match.group(1).strip() if match else ""


def says_yes(value: str) -> bool:
    normalized = value.strip().lower()
    if not normalized:
        return False
    no_words = ("否", "没有", "无", "未出现", "没")
    if any(word in normalized for word in no_words):
        return False
    yes_words = ("是", "有", "出现", "yes", "y", "true", "error", "http", "500", "503")
    return any(word in normalized for word in yes_words)


def says_no(value: str) -> bool:
    normalized = value.strip().lower()
    if not normalized:
        return False
    no_words = ("否", "没有", "无", "未出现", "没", "no", "n", "false")
    return any(word in normalized for word in no_words)


def parse_int(value: str) -> int:
    match = re.search(r"\d+", value or "")
    return int(match.group(0)) if match else 0


def record_kind(record: str) -> str:
    return f"{field_value(record, '记录类型')} {field_value(record, '场景')}"


def is_self_user(record: str) -> bool:
    user = field_value(record, "使用人")
    return any(word in user for word in ("自己", "本人", "我"))


def is_family_user(record: str) -> bool:
    user = field_value(record, "使用人")
    return bool(user) and not is_self_user(record)


def is_independent(record: str) -> bool:
    independent = field_value(record, "是否独立完成")
    needs_explanation = field_value(record, "是否需要解释")
    if says_yes(independent) and not says_yes(needs_explanation):
        return True
    return says_no(needs_explanation) and not says_no(independent)


def successful_count(record: str) -> int:
    count = parse_int(field_value(record, "成功数量"))
    return count if count > 0 else 1


def check_feedback(path: Path, min_records: int, min_photo_repairs: int, min_history_records: int) -> list[Check]:
    if not path.exists():
        return [Check("feedback", "pending", f"{path} not found")]
    records = feedback_records(path)
    if not records:
        return [Check("feedback", "pending", "no real family feedback records yet")]

    checks: list[Check] = [
        Check(
            "feedback_record_count",
            "pass" if len(records) >= min_records else "pending",
            f"{len(records)} records, target {min_records}",
        )
    ]
    for index, record in enumerate(records, start=1):
        technical_error = field_value(record, "是否出现技术错误")
        no_reaction = field_value(record, "是否点完没反应")
        if says_yes(technical_error):
            checks.append(Check("feedback_technical_error", "fail", f"record {index}: {technical_error}"))
        if says_yes(no_reaction):
            checks.append(Check("feedback_no_reaction", "fail", f"record {index}: {no_reaction}"))

    if not any(check.name == "feedback_technical_error" for check in checks):
        checks.append(Check("feedback_technical_error", "pass", "no records report technical errors"))
    if not any(check.name == "feedback_no_reaction" for check in checks):
        checks.append(Check("feedback_no_reaction", "pass", "no records report dead taps/no reaction"))

    self_photo_repairs = 0
    family_photo_flow_records: set[int] = set()
    family_old_photo_records: set[int] = set()
    family_video_sent_records: set[int] = set()
    family_template_sent_records: set[int] = set()
    history_record_count_records: set[int] = set()
    max_history_count = 0

    for record_index, record in enumerate(records, start=1):
        kind = record_kind(record)
        sent = says_yes(field_value(record, "是否发出"))
        independent = is_independent(record)
        if "照片修复" in kind or "选图" in kind or "修照片" in kind:
            if is_self_user(record):
                self_photo_repairs += successful_count(record)
            if is_family_user(record) and independent and sent:
                family_photo_flow_records.add(record_index)
        if "老照片" in kind and is_family_user(record) and independent:
            family_old_photo_records.add(record_index)
        if "动态视频" in kind or "照片动" in kind or "视频" in kind:
            if is_family_user(record) and sent:
                family_video_sent_records.add(record_index)
        if "祝福模板" in kind or "做祝福" in kind or "模板" in kind:
            if is_family_user(record) and sent:
                family_template_sent_records.add(record_index)
        if "历史记录" in kind:
            history_count = parse_int(field_value(record, "历史记录条数"))
            max_history_count = max(max_history_count, history_count)
            if history_count >= min_history_records:
                history_record_count_records.add(record_index)

    scenario_record_sets = [
        family_photo_flow_records,
        family_old_photo_records,
        family_video_sent_records,
        family_template_sent_records,
        history_record_count_records,
    ]
    scenario_record_ids = set().union(*scenario_record_sets)

    checks.extend(
        [
            Check(
                "self_photo_repairs",
                "pass" if self_photo_repairs >= min_photo_repairs else "pending",
                f"{self_photo_repairs}/{min_photo_repairs} successful self photo repairs",
            ),
            Check(
                "family_photo_flow",
                "pass" if family_photo_flow_records else "pending",
                'need family record: "选图 -> 修 -> 发", independent, no explanation, sent',
            ),
            Check(
                "family_old_photo_flow",
                "pass" if family_old_photo_records else "pending",
                "need family old-photo repair record completed independently",
            ),
            Check(
                "family_video_sent",
                "pass" if family_video_sent_records else "pending",
                "need family dynamic-video share record",
            ),
            Check(
                "family_template_sent",
                "pass" if family_template_sent_records else "pending",
                "need family blessing-template share record",
            ),
            Check(
                "history_record_count",
                "pass" if max_history_count >= min_history_records else "pending",
                f"{max_history_count}/{min_history_records} local history records",
            ),
            Check(
                "feedback_distinct_scenarios",
                "pass" if all(scenario_record_sets) and len(scenario_record_ids) >= 5 else "pending",
                f"{len(scenario_record_ids)}/5 distinct family scenario records",
            ),
        ]
    )
    return checks


def check_cost(python: str, days: int, limit_cny: float) -> list[Check]:
    db_path = ROOT / "backend" / "data" / "app.db"
    if not db_path.exists():
        return [Check("cost_report", "pending", f"{db_path} not found; run after real usage")]

    result = subprocess.run(
        [
            python,
            "scripts/cost_report.py",
            "--days",
            str(days),
            "--limit-cny",
            str(limit_cny),
            "--json",
        ],
        cwd=ROOT / "backend",
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode not in (0, 1):
        return [Check("cost_report", "fail", result.stderr.strip() or result.stdout.strip())]
    try:
        report = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        return [Check("cost_report", "fail", f"invalid cost report JSON: {exc}")]

    if int(report.get("counted_jobs") or 0) <= 0:
        return [Check("cost_report", "pending", "no counted real jobs in cost report yet")]
    total = float(report.get("total_estimated_cny") or 0)
    by_device_total = round(sum(float(value or 0) for value in (report.get("by_device") or {}).values()), 4)
    by_type_total = round(sum(float(value or 0) for value in (report.get("by_type") or {}).values()), 4)
    by_day_total = round(sum(float(value or 0) for value in (report.get("by_day") or {}).values()), 4)
    rounded_total = round(total, 4)
    checks = [
        Check(
            "cost_report",
            "pass" if report.get("over_limit") is False else "fail",
            f"total=¥{total:.2f}, limit=¥{limit_cny:.2f}, jobs={report.get('counted_jobs')}",
        ),
        Check(
            "cost_window_days",
            "pass" if int(report.get("days") or 0) == days else "fail",
            f"days={report.get('days')!r}, expected={days}",
        ),
        Check(
            "cost_limit_consistency",
            "pass" if abs(float(report.get("limit_cny") or -1) - limit_cny) <= 1e-9 else "fail",
            f"limit={report.get('limit_cny')!r}, expected={limit_cny:.2f}",
        ),
        Check(
            "cost_by_device_consistency",
            "pass" if abs(by_device_total - rounded_total) <= 0.001 else "fail",
            f"by_device=¥{by_device_total:.4f}, total=¥{rounded_total:.4f}",
        ),
        Check(
            "cost_by_type_consistency",
            "pass" if abs(by_type_total - rounded_total) <= 0.001 else "fail",
            f"by_type=¥{by_type_total:.4f}, total=¥{rounded_total:.4f}",
        ),
        Check(
            "cost_by_day_consistency",
            "pass" if abs(by_day_total - rounded_total) <= 0.001 else "fail",
            f"by_day=¥{by_day_total:.4f}, total=¥{rounded_total:.4f}",
        )
    ]
    return checks


def print_checks(checks: list[Check]) -> None:
    width = max(len(check.name) for check in checks) if checks else 1
    for check in checks:
        marker = {"pass": "PASS", "pending": "PENDING", "fail": "FAIL"}[check.status]
        print(f"{marker:7} {check.name:<{width}}  {check.detail}")


def default_backend_python() -> str:
    bundled = (
        Path.home()
        / ".cache"
        / "codex-runtimes"
        / "codex-primary-runtime"
        / "dependencies"
        / "python"
        / "python.exe"
    )
    if bundled.exists():
        return str(bundled)
    return sys.executable


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate final MVP evidence files.")
    parser.add_argument("--allow-pending", action="store_true", help="Return success when only external evidence is pending.")
    parser.add_argument("--allow-local-urls", action="store_true", help="Allow localhost evidence only for local simulations.")
    parser.add_argument("--deployment", type=Path, default=ROOT / "backend" / "deployment_evidence.json")
    parser.add_argument("--uptime", type=Path, default=ROOT / "backend" / "uptime_evidence.json")
    parser.add_argument("--android-install", type=Path, default=ROOT / "mobile" / "dist" / "install_evidence.json")
    parser.add_argument("--ios-install", type=Path, default=ROOT / "mobile" / "dist" / "ios_install_evidence.json")
    parser.add_argument("--feedback", type=Path, default=ROOT / "feedback.md")
    parser.add_argument("--python", default=default_backend_python())
    parser.add_argument("--cost-days", type=int, default=30)
    parser.add_argument("--cost-limit-cny", type=float, default=300.0)
    parser.add_argument("--min-feedback-records", type=int, default=6)
    parser.add_argument("--min-photo-repairs", type=int, default=10)
    parser.add_argument("--min-history-records", type=int, default=10)
    parser.add_argument("--min-uptime-hours", type=float, default=168.0)
    parser.add_argument("--max-uptime-failure-rate-percent", type=float, default=1.0)
    args = parser.parse_args()

    checks: list[Check] = []
    checks.extend(check_deployment(args.deployment, allow_local_urls=args.allow_local_urls))
    checks.extend(
        check_uptime(
            args.uptime,
            args.min_uptime_hours,
            args.max_uptime_failure_rate_percent,
            allow_local_urls=args.allow_local_urls,
        )
    )
    checks.extend(check_android_install(args.android_install, allow_local_urls=args.allow_local_urls))
    checks.extend(check_ios_install(args.ios_install))
    checks.extend(check_cross_evidence_consistency(args.deployment, args.uptime, args.android_install))
    checks.extend(
        check_feedback(
            args.feedback,
            args.min_feedback_records,
            args.min_photo_repairs,
            args.min_history_records,
        )
    )
    checks.extend(check_cost(args.python, args.cost_days, args.cost_limit_cny))

    print_checks(checks)
    failed = [check for check in checks if check.status == "fail"]
    pending = [check for check in checks if check.status == "pending"]
    print()
    print(f"Summary: {len(failed)} failed, {len(pending)} pending, {len(checks) - len(failed) - len(pending)} passed")

    if failed:
        return 1
    if pending and not args.allow_pending:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
