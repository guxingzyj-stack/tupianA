from app.services.budget import add_estimated_cost
from app.services.cost_report import estimated_cost_report
from app.storage.db import create_job


def test_estimated_cost_report_groups_by_device_type_and_day(tmp_path):
    db_path = str(tmp_path / "app.db")
    create_job(
        "device-a",
        "video",
        metadata=add_estimated_cost({}, reason="video", amount_cny=1.0),
        db_path=db_path,
    )
    create_job(
        "device-a",
        "template",
        metadata=add_estimated_cost({}, reason="template", amount_cny=0.5),
        db_path=db_path,
    )
    create_job(
        "device-b",
        "analyze",
        metadata=add_estimated_cost({}, reason="analyze", amount_cny=0.1),
        db_path=db_path,
    )
    create_job("device-b", "enhance", metadata={}, db_path=db_path)

    report = estimated_cost_report(days=30, db_path=db_path)

    assert report["total_estimated_cny"] == 1.6
    assert report["counted_jobs"] == 3
    assert report["by_device"] == {"device-a": 1.5, "device-b": 0.1}
    assert report["by_type"] == {"analyze": 0.1, "template": 0.5, "video": 1.0}
    assert sum(report["by_day"].values()) == 1.6
