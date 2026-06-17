from app.storage.db import (
    create_job,
    get_job,
    get_or_create_device,
    init_db,
    list_jobs_by_device,
    update_device_config,
    update_job_status,
)


def test_init_db_creates_tables(tmp_path):
    db_path = str(tmp_path / "app.db")
    init_db(db_path)
    assert (tmp_path / "app.db").exists()


def test_create_and_get_job_roundtrip(tmp_path):
    db_path = str(tmp_path / "app.db")
    job = create_job(
        "device-a",
        "analyze",
        status="running",
        input_path="input.jpg",
        metadata={"hello": "world"},
        db_path=db_path,
    )
    fetched = get_job(job["id"], db_path=db_path)
    assert fetched is not None
    assert fetched["device_id"] == "device-a"
    assert fetched["metadata"] == {"hello": "world"}


def test_update_job_status_uses_transaction(tmp_path):
    db_path = str(tmp_path / "app.db")
    job = create_job("device-a", "analyze", db_path=db_path)
    updated = update_job_status(
        job["id"],
        "success",
        output_path="output.jpg",
        metadata={"ok": True},
        db_path=db_path,
    )
    assert updated is not None
    assert updated["status"] == "success"
    assert updated["output_path"] == "output.jpg"
    assert updated["metadata"] == {"ok": True}


def test_list_jobs_by_device_orders_newest_first(tmp_path):
    db_path = str(tmp_path / "app.db")
    first = create_job("device-a", "analyze", db_path=db_path)
    second = create_job("device-a", "enhance", db_path=db_path)
    create_job("device-b", "analyze", db_path=db_path)
    jobs = list_jobs_by_device("device-a", db_path=db_path)
    assert [job["id"] for job in jobs] == [second["id"], first["id"]]


def test_device_config_roundtrip(tmp_path):
    db_path = str(tmp_path / "app.db")
    device = get_or_create_device("device-a", nickname="王奶奶", db_path=db_path)
    assert device["daily_video_limit"] == 10
    updated = update_device_config(
        "device-a",
        daily_budget_cny=8.5,
        enable_video=False,
        config={"share_target": "家人群"},
        db_path=db_path,
    )
    assert updated["daily_budget_cny"] == 8.5
    assert updated["enable_video"] == 0
    assert updated["config"] == {"share_target": "家人群"}

