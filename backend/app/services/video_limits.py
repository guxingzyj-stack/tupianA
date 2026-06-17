from __future__ import annotations

import time

from app.storage.db import count_jobs_by_device_since


def count_video_outputs_today(device_id: str) -> int:
    since = int(time.time()) - 24 * 60 * 60
    return count_jobs_by_device_since(
        device_id,
        job_type="video",
        since_ts=since,
    ) + count_jobs_by_device_since(
        device_id,
        job_type="template",
        since_ts=since,
    )
