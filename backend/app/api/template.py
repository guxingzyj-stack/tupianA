from __future__ import annotations

import asyncio
from pathlib import Path
from typing import Any

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field, model_validator

from app.jobs.queue import enqueue_job, register_handler
from app.engine.local_template import create_local_template_video
from app.services.budget import (
    BUDGET_EXCEEDED_MESSAGE,
    TEMPLATE_COST_CNY,
    BudgetExceeded,
    add_estimated_cost,
    ensure_daily_budget_available,
)
from app.services.video_limits import count_video_outputs_today
from app.storage.db import (
    create_job,
    get_or_create_device,
    update_job_status,
)
from app.storage.files import path_from_public_url, save_base64_image, video_path
from app.templates.catalog import find_template, load_template_catalog

router = APIRouter()


def _requires_old_photo_animation(template: dict[str, Any]) -> bool:
    text = f"{template.get('id', '')} {template.get('name', '')} {template.get('category_name', '')}"
    return "old_photo" in text or "老照片" in text


class TemplateApplyRequest(BaseModel):
    device_id: str = Field(min_length=1, max_length=128)
    template_id: str = Field(min_length=1, max_length=128)
    text_index: int = Field(ge=0, le=4)
    image_url: str | None = None
    image: str | None = None

    @model_validator(mode="after")
    def _has_image_source(self):
        if not self.image_url and not self.image:
            raise ValueError("需要先选一张照片")
        return self


class TemplateApplyResponse(BaseModel):
    job_id: str
    status: str
    estimated_seconds: int


@router.get("/templates")
async def list_templates() -> dict[str, Any]:
    return load_template_catalog()


@router.post("/template/apply", response_model=TemplateApplyResponse)
async def apply_template(payload: TemplateApplyRequest) -> TemplateApplyResponse:
    template = find_template(payload.template_id)
    if template is None:
        raise HTTPException(status_code=404, detail="没有找到这个祝福模板")

    presets = template.get("text_presets") or []
    if payload.text_index >= len(presets):
        raise HTTPException(status_code=400, detail="这句祝福暂时不能用")

    device = get_or_create_device(payload.device_id)
    if not bool(device.get("enable_video", 1)):
        raise HTTPException(status_code=400, detail="视频功能暂时关闭")
    if _requires_old_photo_animation(template) and not bool(device.get("enable_animate_old", 0)):
        raise HTTPException(status_code=400, detail="老照片暂时不做动态")
    try:
        ensure_daily_budget_available(payload.device_id, TEMPLATE_COST_CNY, device=device)
    except BudgetExceeded as exc:
        raise HTTPException(status_code=429, detail=BUDGET_EXCEEDED_MESSAGE) from exc

    used_today = count_video_outputs_today(payload.device_id)
    daily_video_limit = device.get("daily_video_limit")
    if used_today >= int(10 if daily_video_limit is None else daily_video_limit):
        raise HTTPException(status_code=429, detail="今天做的视频有点多,明天再试")

    job = create_job(
        payload.device_id,
        "template",
        status="pending",
        metadata=add_estimated_cost(
            {
                "progress": 0,
                "template_id": template["id"],
                "template_name": template["name"],
                "category_name": template.get("category_name"),
                "text": presets[payload.text_index],
                "estimated_seconds": 20,
            },
            reason="template",
            amount_cny=TEMPLATE_COST_CNY,
        ),
    )

    if payload.image:
        try:
            input_path = save_base64_image(
                device_id=payload.device_id,
                job_id=job["id"],
                image_b64=payload.image,
            )
        except ValueError as exc:
            raise HTTPException(status_code=400, detail="图片格式不对") from exc
    else:
        try:
            input_path = path_from_public_url(payload.image_url or "")
        except ValueError as exc:
            raise HTTPException(status_code=400, detail="这张照片暂时找不到") from exc

    if not Path(input_path).exists():
        raise HTTPException(status_code=400, detail="这张照片暂时找不到")

    update_job_status(job["id"], "pending", input_path=str(input_path), metadata=job["metadata"])
    await enqueue_job(
        job["id"],
        "template",
        {
            "device_id": payload.device_id,
            "input_path": str(input_path),
            "template_id": template["id"],
            "text_index": payload.text_index,
        },
    )
    return TemplateApplyResponse(job_id=job["id"], status="pending", estimated_seconds=20)


async def _handle_template_job(
    job_id: str,
    payload: dict[str, Any],
    set_progress,
) -> dict[str, Any]:
    template = find_template(str(payload["template_id"]))
    if template is None:
        raise RuntimeError("template not found")
    presets = template.get("text_presets") or []
    text_index = int(payload.get("text_index") or 0)
    text = str(presets[text_index])
    target = video_path(str(payload["device_id"]), job_id)

    set_progress(20)
    await asyncio.to_thread(
        create_local_template_video,
        payload["input_path"],
        target,
        template=template,
        text=text,
    )
    set_progress(95)
    return {
        "output_path": str(target),
        "metadata": {
            "processor": "local_template",
            "template_id": template["id"],
            "template_name": template["name"],
            "category_name": template.get("category_name"),
            "text": text,
            "motion": template.get("motion"),
            "watermark": "AI 生成",
        },
    }


register_handler("template", _handle_template_job)
