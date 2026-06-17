from __future__ import annotations

from typing import Any

from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.storage.db import get_or_create_device, update_device_config

router = APIRouter()


class DeviceConfigResponse(BaseModel):
    device_id: str
    nickname: str | None
    daily_budget_cny: float
    daily_video_limit: int
    preferred_style: str | None
    enable_video: bool
    enable_animate_old: bool
    share_target: str | None
    wechat_app_id: str | None
    wechat_universal_link: str | None
    relay_base_url: str | None
    ai_model: str | None
    has_relay_api_key: bool


class DeviceConfigUpdate(BaseModel):
    nickname: str | None = Field(default=None, max_length=40)
    daily_budget_cny: float | None = Field(default=None, ge=0, le=500)
    daily_video_limit: int | None = Field(default=None, ge=0, le=100)
    preferred_style: str | None = Field(default=None, max_length=20)
    enable_video: bool | None = None
    enable_animate_old: bool | None = None
    share_target: str | None = Field(default=None, max_length=80)
    wechat_app_id: str | None = Field(default=None, max_length=120)
    wechat_universal_link: str | None = Field(default=None, max_length=300)
    relay_base_url: str | None = Field(default=None, max_length=300)
    relay_api_key: str | None = Field(default=None, max_length=500)
    ai_model: str | None = Field(default=None, max_length=80)
    clear_relay_api_key: bool = False


@router.get("/devices/{device_id}/config", response_model=DeviceConfigResponse)
async def get_device_config(device_id: str) -> DeviceConfigResponse:
    return _to_response(get_or_create_device(device_id))


@router.put("/devices/{device_id}/config", response_model=DeviceConfigResponse)
async def put_device_config(device_id: str, payload: DeviceConfigUpdate) -> DeviceConfigResponse:
    existing = get_or_create_device(device_id)
    existing_config = dict(existing.get("config") or {})
    config = dict(existing_config)

    for key in (
        "share_target",
        "wechat_app_id",
        "wechat_universal_link",
        "relay_base_url",
        "ai_model",
    ):
        if key in payload.model_fields_set:
            value = getattr(payload, key)
            if value is None or str(value).strip() == "":
                config.pop(key, None)
            else:
                config[key] = str(value).strip()

    if payload.clear_relay_api_key:
        config.pop("relay_api_key", None)
    elif "relay_api_key" in payload.model_fields_set and payload.relay_api_key:
        config["relay_api_key"] = payload.relay_api_key.strip()

    updated = update_device_config(
        device_id,
        nickname=payload.nickname if "nickname" in payload.model_fields_set else None,
        daily_budget_cny=payload.daily_budget_cny,
        daily_video_limit=payload.daily_video_limit,
        preferred_style=payload.preferred_style if "preferred_style" in payload.model_fields_set else None,
        enable_video=payload.enable_video,
        enable_animate_old=payload.enable_animate_old,
        config=config,
    )
    return _to_response(updated)


def _to_response(device: dict[str, Any]) -> DeviceConfigResponse:
    config = device.get("config") or {}
    daily_budget = device.get("daily_budget_cny")
    daily_video_limit = device.get("daily_video_limit")
    return DeviceConfigResponse(
        device_id=device["device_id"],
        nickname=device.get("nickname"),
        daily_budget_cny=float(10.0 if daily_budget is None else daily_budget),
        daily_video_limit=int(10 if daily_video_limit is None else daily_video_limit),
        preferred_style=device.get("preferred_style"),
        enable_video=bool(device.get("enable_video", 1)),
        enable_animate_old=bool(device.get("enable_animate_old", 0)),
        share_target=config.get("share_target"),
        wechat_app_id=config.get("wechat_app_id"),
        wechat_universal_link=config.get("wechat_universal_link"),
        relay_base_url=config.get("relay_base_url"),
        ai_model=config.get("ai_model"),
        has_relay_api_key=bool(config.get("relay_api_key")),
    )
