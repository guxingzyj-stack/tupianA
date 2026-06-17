import pytest

from app.config import get_settings
from app.services.budget import (
    BudgetExceeded,
    add_estimated_cost,
    ensure_daily_budget_available,
    spent_today_cny,
)
from app.storage.db import create_job, update_device_config


def test_budget_counts_estimated_job_costs(monkeypatch, tmp_path):
    monkeypatch.setenv("DB_PATH", str(tmp_path / "app.db"))
    get_settings.cache_clear()
    create_job(
        "d1",
        "video",
        metadata=add_estimated_cost({}, reason="video", amount_cny=1.0),
    )
    create_job(
        "d1",
        "template",
        metadata=add_estimated_cost({}, reason="template", amount_cny=0.5),
    )
    create_job(
        "d2",
        "video",
        metadata=add_estimated_cost({}, reason="video", amount_cny=9.0),
    )

    assert spent_today_cny("d1") == 1.5


def test_budget_rejects_when_next_operation_exceeds_limit(monkeypatch, tmp_path):
    monkeypatch.setenv("DB_PATH", str(tmp_path / "app.db"))
    get_settings.cache_clear()
    update_device_config("d1", daily_budget_cny=1.0)
    create_job(
        "d1",
        "video",
        metadata=add_estimated_cost({}, reason="video", amount_cny=0.8),
    )

    with pytest.raises(BudgetExceeded):
        ensure_daily_budget_available("d1", 0.3)
