from __future__ import annotations

import asyncio
import contextlib
import shutil
import time
from pathlib import Path
from typing import Any

from app.config import Settings
from app.storage.db import delete_jobs_older_than, list_jobs_older_than
from app.storage.files import file_base


async def cleanup_old_storage(retention_hours: int) -> dict[str, int]:
    return await asyncio.to_thread(_cleanup_old_storage_sync, retention_hours)


def start_storage_cleanup_loop(settings: Settings) -> asyncio.Task:
    return asyncio.create_task(_cleanup_loop(settings))


async def _cleanup_loop(settings: Settings) -> None:
    while True:
        await asyncio.sleep(settings.storage_cleanup_interval_seconds)
        with contextlib.suppress(Exception):
            await cleanup_old_storage(settings.storage_retention_hours)


def _cleanup_old_storage_sync(retention_hours: int) -> dict[str, int]:
    cutoff = int(time.time()) - retention_hours * 60 * 60
    old_jobs = list_jobs_older_than(cutoff)
    removed_paths = 0
    for job in old_jobs:
        for path in _paths_for_job(job):
            if _remove_path(path):
                removed_paths += 1
    deleted_jobs = delete_jobs_older_than(cutoff)
    return {"jobs": deleted_jobs, "paths": removed_paths}


def _paths_for_job(job: dict[str, Any]) -> set[Path]:
    paths: set[Path] = set()
    for key in ("input_path", "output_path"):
        value = job.get(key)
        if value:
            paths.add(Path(str(value)))

    metadata = job.get("metadata") or {}
    for key in ("base_image_path", "original_input_path"):
        value = metadata.get(key)
        if value:
            paths.add(Path(str(value)))

    paper = metadata.get("paper_correction")
    if isinstance(paper, dict) and paper.get("path"):
        paths.add(Path(str(paper["path"])))

    output_path = job.get("output_path")
    if output_path:
        path = Path(str(output_path))
        if "outputs" in path.parts:
            paths.add(path.parent)

    return paths


def _remove_path(path: Path) -> bool:
    path = path.resolve()
    base = file_base().resolve()
    try:
        path.relative_to(base)
    except ValueError:
        return False

    if not path.exists():
        return False
    if path.is_dir():
        shutil.rmtree(path)
        return True
    path.unlink()
    _remove_empty_parents(path.parent, base)
    return True


def _remove_empty_parents(path: Path, base: Path) -> None:
    current = path.resolve()
    while current != base and base in current.parents:
        with contextlib.suppress(OSError):
            current.rmdir()
        current = current.parent
