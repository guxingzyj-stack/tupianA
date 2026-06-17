import base64
import time
from io import BytesIO

import cv2
from fastapi.testclient import TestClient
from PIL import Image

from app.config import get_settings
from app.engine.local_video import WATERMARK_TEXT, create_local_motion_video
from app.storage.db import create_job, get_job


def _image_b64() -> str:
    image = Image.new("RGB", (96, 72), (60, 95, 135))
    pixels = image.load()
    for x in range(image.width):
        for y in range(image.height):
            pixels[x, y] = (60 + x // 2, 95 + y // 3, 135)
    buffer = BytesIO()
    image.save(buffer, format="JPEG")
    return base64.b64encode(buffer.getvalue()).decode("ascii")


def _client(monkeypatch, tmp_path) -> TestClient:
    monkeypatch.setenv("DB_PATH", str(tmp_path / "app.db"))
    monkeypatch.setenv("FILE_BASE", str(tmp_path / "files"))
    monkeypatch.setenv("APP_TOKEN", "test-token")
    monkeypatch.setenv("RELAY_BASE_URL", "")
    monkeypatch.setenv("RELAY_API_KEY", "")
    get_settings.cache_clear()
    from app.main import create_app

    return TestClient(create_app())


def test_local_motion_video_writes_readable_mp4(tmp_path):
    source = tmp_path / "source.jpg"
    target = tmp_path / "motion.mp4"
    Image.new("RGB", (96, 72), (80, 110, 150)).save(source)

    create_local_motion_video(
        source,
        target,
        motion="slow_zoom",
        duration_seconds=1,
        fps=6,
    )

    assert target.exists()
    assert target.stat().st_size > 1000
    capture = cv2.VideoCapture(str(target))
    try:
        assert capture.isOpened()
        assert int(capture.get(cv2.CAP_PROP_FRAME_COUNT)) >= 6
        ok, frame = capture.read()
        assert ok
        height, width, _ = frame.shape
        watermark_region = frame[int(height * 0.62) :, int(width * 0.55) :]
        reference_region = frame[0 : int(height * 0.30), 0 : int(width * 0.30)]
        assert watermark_region.mean() < reference_region.mean()
    finally:
        capture.release()

    assert WATERMARK_TEXT == "AI 生成"


def test_video_api_creates_async_job_and_result(monkeypatch, tmp_path):
    headers = {"X-App-Token": "test-token"}
    with _client(monkeypatch, tmp_path) as client:
        analyze = client.post(
            "/api/analyze",
            json={"device_id": "d1", "image": _image_b64()},
            headers=headers,
        )
        assert analyze.status_code == 200
        base_url = analyze.json()["base_image_url"]

        create = client.post(
            "/api/video",
            json={"device_id": "d1", "image_url": base_url, "motion": "slow_zoom"},
            headers=headers,
        )
        assert create.status_code == 200
        job_id = create.json()["job_id"]

        status = None
        for _ in range(30):
            poll = client.get(f"/api/jobs/{job_id}", headers=headers)
            assert poll.status_code == 200
            status = poll.json()
            if status["status"] == "success":
                break
            time.sleep(0.1)

        assert status is not None
        assert status["status"] == "success"
        assert status["progress"] == 100
        stored = get_job(job_id)
        assert stored is not None
        assert stored["metadata"]["watermark"] == "AI 生成"
        result = client.get(status["result_url"])
        assert result.status_code == 200
        assert result.headers["content-type"] == "video/mp4"


def test_video_limit_counts_template_jobs(monkeypatch, tmp_path):
    headers = {"X-App-Token": "test-token"}
    with _client(monkeypatch, tmp_path) as client:
        config = client.put(
            "/api/devices/d1/config",
            json={"daily_video_limit": 1},
            headers=headers,
        )
        assert config.status_code == 200
        create_job("d1", "template", status="success")

        analyze = client.post(
            "/api/analyze",
            json={"device_id": "d1", "image": _image_b64()},
            headers=headers,
        )
        assert analyze.status_code == 200
        base_url = analyze.json()["base_image_url"]

        create = client.post(
            "/api/video",
            json={"device_id": "d1", "image_url": base_url, "motion": "slow_zoom"},
            headers=headers,
        )

        assert create.status_code == 429
        assert create.json()["detail"] == "今天做的视频有点多,明天再试"


def test_video_api_respects_old_photo_animation_disable(monkeypatch, tmp_path):
    headers = {"X-App-Token": "test-token"}
    with _client(monkeypatch, tmp_path) as client:
        config = client.put(
            "/api/devices/d1/config",
            json={"enable_animate_old": False},
            headers=headers,
        )
        assert config.status_code == 200

        analyze = client.post(
            "/api/analyze",
            json={"device_id": "d1", "image": _image_b64()},
            headers=headers,
        )
        assert analyze.status_code == 200
        base_url = analyze.json()["base_image_url"]

        create = client.post(
            "/api/video",
            json={
                "device_id": "d1",
                "image_url": base_url,
                "motion": "slow_zoom",
                "is_old_photo": True,
            },
            headers=headers,
        )

        assert create.status_code == 400
        assert create.json()["detail"] == "老照片暂时不做动态"


def test_video_api_respects_daily_budget(monkeypatch, tmp_path):
    headers = {"X-App-Token": "test-token"}
    with _client(monkeypatch, tmp_path) as client:
        config = client.put(
            "/api/devices/d1/config",
            json={"daily_budget_cny": 0.5},
            headers=headers,
        )
        assert config.status_code == 200

        analyze = client.post(
            "/api/analyze",
            json={"device_id": "d1", "image": _image_b64()},
            headers=headers,
        )
        assert analyze.status_code == 200
        base_url = analyze.json()["base_image_url"]

        create = client.post(
            "/api/video",
            json={"device_id": "d1", "image_url": base_url, "motion": "slow_zoom"},
            headers=headers,
        )

        assert create.status_code == 429
        assert create.json()["detail"] == "今天的预算用完了,明天再试"
