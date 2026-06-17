from __future__ import annotations

import time
from typing import Any

from app.config import get_settings
from app.storage.db import get_or_create_device, list_jobs_by_device_since


BUDGET_EXCEEDED_MESSAGE = "今天的预算用完了,明天再试"

ANALYZE_COST_CNY = 0.10
OLD_PHOTO_RESTORE_COST_CNY = 0.50
VIDEO_COST_CNY = 1.00
TEMPLATE_COST_CNY = 1.00


class BudgetExceeded(Exception):
    pass


def estimate_analyze_cost(device: dict[str, Any]) -> float:
    config = device.get("config") or {}
    settings = get_settings()
    has_relay = bool(
        (config.get("relay_base_url") or settings.relay_base_url)
        and (config.get("relay_api_key") or settings.relay_api_key)
    )
    return ANALYZE_COST_CNY if has_relay else 0.0


def ensure_daily_budget_available(
    device_id: str,
    estimated_cost_cny: float,
    *,
    device: dict[str, Any] | None = None,
) -> None:
    if estimated_cost_cny <= 0:
        return
    resolved_device = device or get_or_create_device(device_id)
    daily_budget = float(resolved_device.get("daily_budget_cny") or 0)
    if spent_today_cny(device_id) + estimated_cost_cny > daily_budget + 1e-9:
        raise BudgetExceeded(BUDGET_EXCEEDED_MESSAGE)


def spent_today_cny(device_id: str) -> float:
    since = int(time.time()) - 24 * 60 * 60
    total = 0.0
    for job in list_jobs_by_device_since(device_id, since_ts=since):
        metadata = job.get("metadata") or {}
        try:
            total += float(metadata.get("estimated_cost_cny") or 0)
        except (TypeError, ValueError):
            continue
    return round(total, 4)


def add_estimated_cost(
    metadata: dict[str, Any],
    *,
    reason: str,
    amount_cny: float,
) -> dict[str, Any]:
    if amount_cny <= 0:
        return metadata
    updated = dict(metadata)
    costs = list(updated.get("estimated_costs") or [])
    costs.append({"reason": reason, "amount_cny": amount_cny})
    updated["estimated_costs"] = costs
    updated["estimated_cost_cny"] = round(
        sum(_cost_amount(item) for item in costs),
        4,
    )
    return updated


def _cost_amount(item: Any) -> float:
    if not isinstance(item, dict):
        return 0.0
    try:
        return float(item.get("amount_cny") or 0)
    except (TypeError, ValueError):
        return 0.0
