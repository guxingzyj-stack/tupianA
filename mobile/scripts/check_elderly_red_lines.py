from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


MOBILE_ROOT = Path(__file__).resolve().parents[1]
LIB_ROOT = MOBILE_ROOT / "lib"
SKIPPED_PARTS = {"dev"}


FORBIDDEN_TEXT_TERMS = {
    "会员": "v0.1 自用版不能出现会员/付费入口",
    "充值": "v0.1 自用版不能出现充值入口",
    "开通": "v0.1 自用版不能出现开通付费提示",
    "订阅": "v0.1 自用版不能出现订阅提示",
    "登录": "v0.1 自用版不需要登录",
    "注册": "v0.1 自用版不需要注册",
    "广告": "PRD 禁止任何广告",
    "签到": "PRD 禁止任务/签到式干扰",
    "曝光": "老人界面不能出现专业修图词",
    "HDR": "老人界面不能出现专业修图词",
    "EV": "老人界面不能出现专业修图词",
    "色温": "老人界面不能出现专业修图词",
    "饱和度": "老人界面不能出现专业修图词",
    "对比度": "老人界面不能出现专业修图词",
    "锐化": "老人界面不能出现专业修图词",
    "降噪": "老人界面不能出现专业修图词",
    "token": "老人界面不能出现技术配置词",
    "Token": "老人界面不能出现技术配置词",
    "API": "老人界面不能出现技术缩写",
    "HTTP": "老人界面不能出现技术缩写",
    "JSON": "老人界面不能出现技术缩写",
    "Error": "老人界面不能出现英文技术错误",
    "Exception": "老人界面不能出现英文技术错误",
    "Field required": "老人界面不能出现后端校验细节",
    "503": "老人界面不能出现技术错误码",
    "500": "老人界面不能出现技术错误码",
}

ALLOWED_TEXTS = {
    "AI 生成",  # PRD §8.2 requires this watermark on generated videos.
    "X-App-Token",  # Request header constant, not a user-facing string.
    "清除已保存的 API Key",  # Hidden child configuration from PRD §11.
}

STRING_RE = re.compile(
    r"""(?P<prefix>r)?(?P<quote>['"])(?P<body>(?:\\.|(?!\2).)*)(?P=quote)"""
)
FONT_SIZE_RE = re.compile(r"fontSize\s*:\s*([0-9]+(?:\.[0-9]+)?)")


@dataclass(frozen=True)
class Finding:
    path: Path
    line: int
    message: str


def has_cjk(text: str) -> bool:
    return any("\u4e00" <= char <= "\u9fff" for char in text)


def iter_dart_files() -> list[Path]:
    return sorted(
        path
        for path in LIB_ROOT.rglob("*.dart")
        if not any(part in SKIPPED_PARTS for part in path.relative_to(LIB_ROOT).parts)
    )


def check_user_strings(path: Path, text: str) -> list[Finding]:
    findings: list[Finding] = []
    for line_no, line in enumerate(text.splitlines(), start=1):
        for match in STRING_RE.finditer(line):
            body = match.group("body")
            stripped = body.strip()
            if not stripped or stripped in ALLOWED_TEXTS:
                continue
            if "AI" in stripped and stripped != "AI 生成":
                findings.append(
                    Finding(path, line_no, f'避免在老人界面使用英文缩写: "{stripped}"')
                )
            if not has_cjk(stripped):
                continue
            for term, reason in FORBIDDEN_TEXT_TERMS.items():
                if term in stripped:
                    findings.append(
                        Finding(path, line_no, f'{reason}: "{stripped}"')
                    )
    return findings


def check_font_sizes(path: Path, text: str) -> list[Finding]:
    findings: list[Finding] = []
    for line_no, line in enumerate(text.splitlines(), start=1):
        for match in FONT_SIZE_RE.finditer(line):
            value = float(match.group(1))
            if value < 16:
                findings.append(
                    Finding(
                        path,
                        line_no,
                        f"PRD §4.1 禁止小于 16 的字号: fontSize {value:g}",
                    )
                )
    return findings


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Check mobile UI text and font-size red lines for elder users."
    )
    parser.add_argument("--json", action="store_true", help="Reserved for CI use.")
    args = parser.parse_args()
    _ = args

    if not LIB_ROOT.exists():
        print(f"Missing Flutter lib directory: {LIB_ROOT}", file=sys.stderr)
        return 2

    findings: list[Finding] = []
    for path in iter_dart_files():
        text = path.read_text(encoding="utf-8")
        findings.extend(check_user_strings(path, text))
        findings.extend(check_font_sizes(path, text))

    if findings:
        print("Elderly red-line check failed:")
        for finding in findings:
            rel = finding.path.relative_to(MOBILE_ROOT)
            print(f"  {rel}:{finding.line}: {finding.message}")
        return 1

    print("Elderly red-line check passed")
    print(f"  scanned_files: {len(iter_dart_files())}")
    print("  forbidden_terms: none")
    print("  font_size_under_16: none")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
