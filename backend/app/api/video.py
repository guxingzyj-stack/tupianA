from __future__ import annotations

import asyncio
from pathlib import Path
from typing import Any

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.engine.local_video import ALLOWED_MOTIONS, MOTION_LABELS, create_local_motion_video
from app.jobs.queue import enqueue_job, register_handler
from app.services.budget import (
    BUDGET_EXCEEDED_MESSAGE,
    VIDEO_COST_CNY,
    BudgetExceeded,
    add_estimated_cost,
    ensure_daily_budget_available,
)
from app.services.video_limits import count_video_outputs_today
from app.storage.db import create_job, get_job, get_or_create_device
from app.storage.files import path_from_public_url, public_url_for_path, video_path

router = APIRouter()


class VideoRequest(BaseModel):
    device_id: str = Field(min_length=1, max_length=128)
    image_url: str = Field(min_length=1)
    motion: str = Field(default="slow_zoom")
    is_old_photo: bool = False


class VideoResponse(BaseModel):
    job_id: str
    status: str
    estimated_seconds: int


class JobStatusResponse(BaseModel):
    job_id: str
    status: str
    progress: int
    result_url: str | None = None
    error: str | None = None


@router.post("/video", response_model=VideoResponse)
async def create_video(payload: VideoRequest) -> VideoResponse:
    if payload.motion not in ALLOWED_MOTIONS:
        raise HTTPException(status_code=400, detail="这个动态方式不存在")

    try:
        input_path = path_from_public_url(payload.image_url)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail="这张照片暂时找不到") from exc
    if not input_path.exists():
        raise HTTPException(status_code=400, detail="这张照片暂时找不到")

    device = get_or_create_device(payload.device_id)
    if not bool(device.get("enable_video", 1)):
        raise HTTPException(status_code=400, detail="视频功能暂时关闭")
    if payload.is_old_photo and not bool(device.get("enable_animate_old", 0)):
        raise HTTPException(status_code=400, detail="老照片暂时不做动态")
    try:
        ensure_daily_budget_available(payload.device_id, VIDEO_COST_CNY, device=device)
    except BudgetExceeded as exc:
        raise HTTPException(status_code=429, detail=BUDGET_EXCEEDED_MESSAGE) from exc

    used_today = count_video_outputs_today(payload.device_id)
    daily_video_limit = device.get("daily_video_limit")
    if used_today >= int(10 if daily_video_limit is None else daily_video_limit):
        raise HTTPException(status_code=429, detail="今天做的视频有点多,明天再试")

    job = create_job(
        payload.device_id,
        "video",
        status="pending",
        input_path=str(input_path),
        metadata=add_estimated_cost(
            {
                "progress": 0,
                "motion": payload.motion,
                "motion_name": MOTION_LABELS[payload.motion],
                "estimated_seconds": 20,
            },
            reason="video",
            amount_cny=VIDEO_COST_CNY,
        ),
    )
    await enqueue_job(
        job["id"],
        "video",
        {
            "device_id": payload.device_id,
            "input_path": str(input_path),
            "motion": payload.motion,
        },
    )
    return VideoResponse(job_id=job["id"], status="pending", estimated_seconds=20)


@router.get("/jobs/{job_id}", response_model=JobStatusResponse)
async def get_job_status(job_id: str, request: Request) -> JobStatusResponse:
    job = get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="没有找到这个任务")

    metadata: dict[str, Any] = job.get("metadata") or {}
    result_url = None
    if job["status"] == "success" and job.get("output_path"):
        result_url = public_url_for_path(job["output_path"], request)

    return JobStatusResponse(
        job_id=job["id"],
        status=job["status"],
        progress=int(metadata.get("progress") or 0),
        result_url=result_url,
        error=job.get("error_msg") if job["status"] == "failed" else None,
    )


async def _handle_video_job(
    job_id: str,
    payload: dict[str, Any],
    set_progress,
) -> dict[str, Any]:
    input_path = Path(payload["input_path"])
    device_id = str(payload["device_id"])
    motion = str(payload["motion"])
    target = video_path(device_id, job_id)

    set_progress(15)
    await asyncio.to_thread(
        create_local_motion_video,
        input_path,
        target,
        motion=motion,
    )
    set_progress(95)
    return {
        "output_path": str(target),
        "metadata": {
            "processor": "local_motion",
            "motion": motion,
            "motion_name": MOTION_LABELS.get(motion, motion),
            "watermark": "AI 生成",
        },
    }


register_handler("video", _handle_video_job)
