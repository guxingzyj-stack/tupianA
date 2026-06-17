from __future__ import annotations

import time
from datetime import datetime, timezone
from typing import Any

from app.storage.db import list_jobs_since


def estimated_cost_report(
    *,
    days: int = 30,
    db_path: str | None = None,
) -> dict[str, Any]:
    since_ts = int(time.time()) - days * 24 * 60 * 60
    jobs = list_jobs_since(since_ts, db_path=db_path)

    total = 0.0
    by_device: dict[str, float] = {}
    by_type: dict[str, float] = {}
    by_day: dict[str, float] = {}
    counted_jobs = 0

    for job in jobs:
        cost = _job_cost(job)
        if cost <= 0:
            continue
        counted_jobs += 1
        total += cost
        device_id = str(job.get("device_id") or "unknown")
        job_type = str(job.get("type") or "unknown")
        day = datetime.fromtimestamp(int(job["created_at"]), tz=timezone.utc).strftime("%Y-%m-%d")
        by_device[device_id] = by_device.get(device_id, 0.0) + cost
        by_type[job_type] = by_type.get(job_type, 0.0) + cost
        by_day[day] = by_day.get(day, 0.0) + cost

    return {
        "days": days,
        "total_estimated_cny": round(total, 4),
        "counted_jobs": counted_jobs,
        "by_device": _rounded_map(by_device),
        "by_type": _rounded_map(by_type),
        "by_day": _rounded_map(dict(sorted(by_day.items()))),
    }


def _job_cost(job: dict[str, Any]) -> float:
    metadata = job.get("metadata") or {}
    try:
        return float(metadata.get("estimated_cost_cny") or 0)
    except (TypeError, ValueError):
        return 0.0


def _rounded_map(values: dict[str, float]) -> dict[str, float]:
    return {key: round(value, 4) for key, value in sorted(values.items())}
