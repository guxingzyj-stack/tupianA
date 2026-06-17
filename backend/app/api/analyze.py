from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.adapters.base import AdapterFailure
from app.adapters.claude_adapter import ClaudeAdapter
from app.engine.document_scanner import correct_paper_photo
from app.engine.old_photo_detector import is_old_photo, old_photo_options_for
from app.engine.param_enhance import apply_basic_enhancement
from app.prompts.analyze_prompt import PROMPT_VERSION, SCHEMA_VALIDATOR, fallback_analysis
from app.services.budget import (
    BUDGET_EXCEEDED_MESSAGE,
    BudgetExceeded,
    add_estimated_cost,
    ensure_daily_budget_available,
    estimate_analyze_cost,
)
from app.storage.db import create_job, get_or_create_device, update_job_status
from app.storage.files import output_dir, public_url_for_path, save_base64_image

router = APIRouter()


class AnalyzeRequest(BaseModel):
    device_id: str = Field(min_length=1)
    image: str = Field(min_length=1)
    is_shot_paper: bool = False


class OptionResponse(BaseModel):
    name: str
    intent: str


class AnalysisResponse(BaseModel):
    scene: str
    subject: str
    problems: list[str]
    options: list[OptionResponse]


class AnalyzeResponse(BaseModel):
    job_id: str
    base_image_url: str
    analysis: AnalysisResponse
    is_old_photo: bool = False


@router.post("/analyze", response_model=AnalyzeResponse)
async def analyze_photo(payload: AnalyzeRequest, request: Request) -> AnalyzeResponse:
    device = get_or_create_device(payload.device_id)
    analyze_cost = estimate_analyze_cost(device)
    try:
        ensure_daily_budget_available(payload.device_id, analyze_cost, device=device)
    except BudgetExceeded as exc:
        raise HTTPException(status_code=429, detail=BUDGET_EXCEEDED_MESSAGE) from exc

    job = create_job(payload.device_id, "analyze", status="running")
    job_id = job["id"]

    try:
        input_path = save_base64_image(
            device_id=payload.device_id,
            job_id=job_id,
            image_b64=payload.image,
        )
    except ValueError as exc:
        update_job_status(job_id, "failed", error_msg="图片格式不对")
        raise HTTPException(status_code=400, detail="图片格式不对") from exc

    outputs = output_dir(payload.device_id, job_id)
    processing_path = input_path
    paper_corrected = False
    if payload.is_shot_paper:
        processing_path, paper_corrected = correct_paper_photo(
            input_path,
            outputs / "paper_corrected.jpg",
        )

    base_path = outputs / "base.jpg"
    try:
        apply_basic_enhancement(processing_path, base_path)
    except Exception as exc:
        update_job_status(job_id, "failed", input_path=str(input_path), error_msg="图片处理失败")
        raise HTTPException(status_code=400, detail="图片格式不对") from exc

    analysis = await _safe_analyze(payload.image, payload.device_id)
    is_old, old_photo_signals = is_old_photo(processing_path, analysis.get("scene", ""))
    if is_old:
        analysis = {
            **analysis,
            "scene": analysis.get("scene") or "老照片",
            "options": old_photo_options_for(processing_path),
        }
    metadata: dict[str, Any] = {
        "analysis": analysis,
        "prompt_version": PROMPT_VERSION,
        "base_image_path": str(base_path),
        "original_input_path": str(input_path),
        "paper_correction": {
            "requested": payload.is_shot_paper,
            "corrected": paper_corrected,
            "path": str(processing_path),
        },
        "old_photo": {
            "is_old": is_old,
            "signals": old_photo_signals,
        },
    }
    metadata = add_estimated_cost(
        metadata,
        reason="analyze",
        amount_cny=analyze_cost,
    )
    update_job_status(
        job_id,
        "success",
        input_path=str(processing_path),
        output_path=str(base_path),
        metadata=metadata,
    )

    return AnalyzeResponse(
        job_id=job_id,
        base_image_url=public_url_for_path(base_path, request),
        analysis=analysis,
        is_old_photo=is_old,
    )


async def _safe_analyze(image_b64: str, device_id: str) -> dict[str, Any]:
    device = get_or_create_device(device_id)
    config = device.get("config") or {}
    adapter = ClaudeAdapter(
        relay_base_url=config.get("relay_base_url"),
        relay_api_key=config.get("relay_api_key"),
        ai_model=config.get("ai_model"),
    )
    try:
        result = await adapter.analyze(image_b64=image_b64)
    except AdapterFailure:
        return fallback_analysis()
    if not SCHEMA_VALIDATOR(result):
        return fallback_analysis()
    return result
