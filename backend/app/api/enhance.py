from __future__ import annotations

import time
from pathlib import Path
from typing import Any

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.engine.intent_mapper import parse_intent
from app.engine.old_photo_restore import is_old_photo_intent
from app.engine.param_enhance import apply_operations
from app.services.budget import (
    BUDGET_EXCEEDED_MESSAGE,
    OLD_PHOTO_RESTORE_COST_CNY,
    BudgetExceeded,
    add_estimated_cost,
    ensure_daily_budget_available,
)
from app.services.old_photo_restore_service import restore_old_photo
from app.storage.db import get_job, update_job_status
from app.storage.files import output_dir, public_url_for_path

router = APIRouter()


class EnhanceRequest(BaseModel):
    job_id: str = Field(min_length=1)
    option_index: int = Field(ge=0, le=2)


class EnhanceResponse(BaseModel):
    result_image_url: str
    processing_ms: int


@router.post("/enhance", response_model=EnhanceResponse)
async def enhance_photo(payload: EnhanceRequest, request: Request) -> EnhanceResponse:
    started = time.perf_counter()
    job = get_job(payload.job_id)
    if not job:
        raise HTTPException(status_code=404, detail="没有找到这次修图")
    if not job.get("input_path") or not Path(job["input_path"]).exists():
        raise HTTPException(status_code=404, detail="原照片找不到了")

    metadata: dict[str, Any] = job.get("metadata") or {}
    analysis = metadata.get("analysis") or {}
    options = analysis.get("options") or []
    if payload.option_index >= len(options):
        raise HTTPException(status_code=400, detail="这个修法不存在")

    option = options[payload.option_index]
    intent = option.get("intent", "")
    option_name = option.get("name", "")
    operations = parse_intent(intent)
    old_photo_meta = metadata.get("old_photo") or {}
    should_restore_old_photo = bool(old_photo_meta.get("is_old")) or is_old_photo_intent(
        intent,
        option_name,
    )
    target = output_dir(job["device_id"], job["id"]) / f"option_{payload.option_index + 1}.jpg"

    if not target.exists():
        if should_restore_old_photo:
            try:
                ensure_daily_budget_available(job["device_id"], OLD_PHOTO_RESTORE_COST_CNY)
            except BudgetExceeded as exc:
                raise HTTPException(status_code=429, detail=BUDGET_EXCEEDED_MESSAGE) from exc

        try:
            if should_restore_old_photo:
                _, processor = await restore_old_photo(
                    job["input_path"],
                    target,
                    intent=intent,
                    option_name=option_name,
                )
                processors = dict(metadata.get("restore_processors") or {})
                processors[str(payload.option_index)] = processor
                metadata["restore_processors"] = processors
                metadata = add_estimated_cost(
                    metadata,
                    reason=f"old_photo_restore:{payload.option_index}",
                    amount_cny=OLD_PHOTO_RESTORE_COST_CNY,
                )
            else:
                apply_operations(job["input_path"], operations, target)
        except Exception as exc:
            update_job_status(job["id"], "failed", error_msg="修图失败")
            raise HTTPException(status_code=400, detail="这张照片暂时修不了") from exc

    enhanced = dict(metadata.get("enhanced_images") or {})
    enhanced[str(payload.option_index)] = str(target)
    metadata["enhanced_images"] = enhanced
    update_job_status(
        job["id"],
        job["status"],
        output_path=str(target),
        metadata=metadata,
    )

    return EnhanceResponse(
        result_image_url=public_url_for_path(target, request),
        processing_ms=int((time.perf_counter() - started) * 1000),
    )
