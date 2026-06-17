import asyncio
import time

from app.config import get_settings
from app.services.storage_cleanup import cleanup_old_storage
from app.storage.db import create_job, get_db, get_job


def test_storage_cleanup_removes_old_job_files(monkeypatch, tmp_path):
    file_base = tmp_path / "files"
    db_path = tmp_path / "app.db"
    monkeypatch.setenv("FILE_BASE", str(file_base))
    monkeypatch.setenv("DB_PATH", str(db_path))
    get_settings.cache_clear()

    input_path = file_base / "inputs" / "d1" / "old.jpg"
    output_dir = file_base / "outputs" / "d1" / "job-old"
    output_path = output_dir / "base.jpg"
    video_path = file_base / "videos" / "d1" / "job-old.mp4"
    outside_path = tmp_path / "outside.jpg"
    for path in (input_path, output_path, video_path, outside_path):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"data")

    old_job = create_job(
        "d1",
        "analyze",
        job_id="job-old",
        input_path=str(input_path),
        output_path=str(output_path),
        metadata={
            "base_image_path": str(output_path),
            "paper_correction": {"path": str(output_dir / "paper.jpg")},
        },
    )
    create_job(
        "d1",
        "video",
        job_id="job-video",
        input_path=str(outside_path),
        output_path=str(video_path),
    )
    fresh_job = create_job(
        "d1",
        "analyze",
        job_id="job-fresh",
        input_path=str(file_base / "inputs" / "d1" / "fresh.jpg"),
    )

    old_ts = int(time.time()) - 48 * 60 * 60
    with get_db(str(db_path)) as conn:
        conn.execute(
            "UPDATE jobs SET created_at = ?, updated_at = ? WHERE id IN (?, ?)",
            (old_ts, old_ts, old_job["id"], "job-video"),
        )
        conn.commit()

    result = asyncio.run(cleanup_old_storage(24))

    assert result["jobs"] == 2
    assert result["paths"] >= 2
    assert get_job("job-old", db_path=str(db_path)) is None
    assert get_job("job-video", db_path=str(db_path)) is None
    assert get_job(fresh_job["id"], db_path=str(db_path)) is not None
    assert not input_path.exists()
    assert not output_dir.exists()
    assert not video_path.exists()
    assert outside_path.exists()
