from __future__ import annotations

import argparse
import os
from pathlib import Path


DEV_TOKEN = "dev-token-change-me"


def main() -> None:
    parser = argparse.ArgumentParser(description="Check backend environment before deploy.")
    parser.add_argument("--allow-local-dev", action="store_true")
    args = parser.parse_args()

    errors: list[str] = []
    warnings: list[str] = []

    app_token = os.getenv("APP_TOKEN", "")
    relay_base_url = os.getenv("RELAY_BASE_URL", "")
    relay_api_key = os.getenv("RELAY_API_KEY", "")
    db_path = os.getenv("DB_PATH", "./data/app.db")
    file_base = os.getenv("FILE_BASE", "./data/files")
    public_base_url = os.getenv("PUBLIC_BASE_URL", "")
    storage_retention_hours = _int_env("STORAGE_RETENTION_HOURS", 24, errors)
    cleanup_interval = _int_env("STORAGE_CLEANUP_INTERVAL_SECONDS", 3600, errors)
    rate_limit = _int_env("RATE_LIMIT_PER_MINUTE", 60, errors)
    worker_count = _int_env("WORKER_COUNT", 2, errors)

    if not app_token:
        _local_or_error(
            args.allow_local_dev,
            errors,
            warnings,
            f"APP_TOKEN is not set; local scripts may fall back to {DEV_TOKEN}.",
        )
    elif app_token == DEV_TOKEN:
        _local_or_error(args.allow_local_dev, errors, warnings, "APP_TOKEN is still the dev token.")
    elif len(app_token) < 16:
        errors.append("APP_TOKEN should be at least 16 characters.")

    if not relay_base_url or not relay_api_key:
        _local_or_error(
            args.allow_local_dev,
            errors,
            warnings,
            "RELAY_BASE_URL and RELAY_API_KEY should be configured for deployed AI analysis.",
        )

    if relay_base_url and not relay_base_url.startswith("https://"):
        errors.append("RELAY_BASE_URL should start with https://.")

    if not args.allow_local_dev:
        if not _is_volume_path(db_path):
            errors.append("DB_PATH should point to a persistent volume path, for example /volume/app.db.")
        if not _is_volume_path(file_base):
            errors.append("FILE_BASE should point to a persistent volume path, for example /volume/files.")
        if public_base_url and not public_base_url.startswith("https://"):
            errors.append("PUBLIC_BASE_URL should start with https:// when set.")

    if storage_retention_hours < 1:
        errors.append("STORAGE_RETENTION_HOURS must be >= 1.")
    if cleanup_interval < 60:
        errors.append("STORAGE_CLEANUP_INTERVAL_SECONDS must be >= 60.")
    if rate_limit < 1:
        errors.append("RATE_LIMIT_PER_MINUTE must be >= 1.")
    if worker_count < 1:
        errors.append("WORKER_COUNT must be >= 1.")

    if warnings:
        print("Warnings:")
        for warning in warnings:
            print(f"  - {warning}")

    if errors:
        print("Environment check failed:")
        for error in errors:
            print(f"  - {error}")
        raise SystemExit(1)

    print("Environment check passed.")


def _int_env(name: str, default: int, errors: list[str]) -> int:
    value = os.getenv(name, str(default))
    try:
        return int(value)
    except ValueError:
        errors.append(f"{name} must be an integer.")
        return default


def _local_or_error(
    allow_local_dev: bool,
    errors: list[str],
    warnings: list[str],
    message: str,
) -> None:
    if allow_local_dev:
        warnings.append(message)
    else:
        errors.append(message)


def _is_volume_path(path: str) -> bool:
    normalized = Path(path).as_posix()
    return normalized.startswith("/volume/")


if __name__ == "__main__":
    main()
