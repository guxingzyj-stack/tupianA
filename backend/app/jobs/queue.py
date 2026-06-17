from __future__ import annotations

import asyncio
from dataclasses import dataclass
from typing import Any, Awaitable, Callable

from app.storage.db import get_job, update_job_status


ProgressCallback = Callable[[int], None]
JobHandler = Callable[[str, dict[str, Any], ProgressCallback], Awaitable[dict[str, Any]]]


@dataclass(frozen=True)
class QueuedJob:
    job_id: str
    job_type: str
    payload: dict[str, Any]


class JobQueue:
    def __init__(self) -> None:
        self._queue: asyncio.Queue[QueuedJob] = asyncio.Queue()
        self._handlers: dict[str, JobHandler] = {}
        self._workers: list[asyncio.Task[None]] = []
        self._worker_count = 0

    def register_handler(self, job_type: str, handler: JobHandler) -> None:
        self._handlers[job_type] = handler

    async def start(self, worker_count: int) -> None:
        self._workers = [worker for worker in self._workers if not worker.done()]
        if self._workers:
            return
        self._worker_count = worker_count
        for index in range(worker_count):
            self._workers.append(asyncio.create_task(self._worker_loop(index)))

    async def stop(self) -> None:
        for worker in self._workers:
            worker.cancel()
        if self._workers:
            await asyncio.gather(*self._workers, return_exceptions=True)
        self._workers.clear()

    async def enqueue(self, job_id: str, job_type: str, payload: dict[str, Any]) -> None:
        self._workers = [worker for worker in self._workers if not worker.done()]
        if not self._workers:
            await self.start(1)
        await self._queue.put(QueuedJob(job_id=job_id, job_type=job_type, payload=payload))

    async def _worker_loop(self, worker_index: int) -> None:
        while True:
            queued = await self._queue.get()
            try:
                await self._run_job(queued)
            finally:
                self._queue.task_done()

    async def _run_job(self, queued: QueuedJob) -> None:
        handler = self._handlers.get(queued.job_type)
        if handler is None:
            update_job_status(
                queued.job_id,
                "failed",
                error_msg="这个任务暂时做不了",
            )
            return

        job = get_job(queued.job_id)
        metadata = dict(job.get("metadata") or {}) if job else {}
        metadata["progress"] = 5
        update_job_status(queued.job_id, "running", metadata=metadata)

        def set_progress(progress: int) -> None:
            current_job = get_job(queued.job_id)
            current_metadata = dict(current_job.get("metadata") or {}) if current_job else {}
            current_metadata["progress"] = max(0, min(progress, 99))
            update_job_status(queued.job_id, "running", metadata=current_metadata)

        try:
            result = await handler(queued.job_id, queued.payload, set_progress)
        except Exception as exc:
            failed_job = get_job(queued.job_id)
            failed_metadata = dict(failed_job.get("metadata") or {}) if failed_job else {}
            failed_metadata["progress"] = 100
            update_job_status(
                queued.job_id,
                "failed",
                metadata=failed_metadata,
                error_msg="制作失败了,稍后再试",
            )
            return

        finished_job = get_job(queued.job_id)
        finished_metadata = dict(finished_job.get("metadata") or {}) if finished_job else {}
        finished_metadata.update(result.get("metadata") or {})
        finished_metadata["progress"] = 100
        update_job_status(
            queued.job_id,
            "success",
            output_path=result.get("output_path"),
            metadata=finished_metadata,
        )


_queue = JobQueue()


def get_registered_queue() -> JobQueue:
    return _queue


def register_handler(job_type: str, handler: JobHandler) -> None:
    _queue.register_handler(job_type, handler)


async def enqueue_job(job_id: str, job_type: str, payload: dict[str, Any]) -> None:
    await _queue.enqueue(job_id, job_type, payload)
