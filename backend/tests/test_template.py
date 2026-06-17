import base64
import time
from io import BytesIO

from fastapi.testclient import TestClient
from PIL import Image

from app.config import get_settings
from app.storage.db import get_job


def _image_b64() -> str:
    image = Image.new("RGB", (120, 86), (94, 118, 145))
    pixels = image.load()
    for x in range(image.width):
        for y in range(image.height):
            pixels[x, y] = (94 + x // 4, 118 + y // 4, 145)
    buffer = BytesIO()
    image.save(buffer, format="JPEG")
    return base64.b64encode(buffer.getvalue()).decode("ascii")


def _client(monkeypatch, tmp_path) -> TestClient:
    monkeypatch.setenv("DB_PATH", str(tmp_path / "app.db"))
    monkeypatch.setenv("FILE_BASE", str(tmp_path / "files"))
    monkeypatch.setenv("APP_TOKEN", "test-token")
    monkeypatch.setenv("RATE_LIMIT_PER_MINUTE", "1000")
    monkeypatch.setenv("RELAY_BASE_URL", "")
    monkeypatch.setenv("RELAY_API_KEY", "")
    get_settings.cache_clear()
    from app.main import create_app

    return TestClient(create_app())


def test_template_catalog_has_prd_categories(monkeypatch, tmp_path):
    with _client(monkeypatch, tmp_path) as client:
        response = client.get("/api/templates", headers={"X-App-Token": "test-token"})

    assert response.status_code == 200
    categories = response.json()["categories"]
    assert [item["name"] for item in categories] == ["节日祝福", "生日", "让照片动", "全家福"]
    assert sum(len(category["templates"]) for category in categories) == 24
    assert all(len(item["name"]) <= 5 for category in categories for item in category["templates"])


def test_template_apply_creates_async_video(monkeypatch, tmp_path):
    headers = {"X-App-Token": "test-token"}
    with _client(monkeypatch, tmp_path) as client:
        create = client.post(
            "/api/template/apply",
            json={
                "device_id": "d1",
                "template_id": "midautumn_reunion",
                "text_index": 0,
                "image": _image_b64(),
            },
            headers=headers,
        )
        assert create.status_code == 200
        job_id = create.json()["job_id"]

        status = None
        for _ in range(100):
            poll = client.get(f"/api/jobs/{job_id}", headers=headers)
            assert poll.status_code == 200
            status = poll.json()
            if status["status"] == "success":
                break
            time.sleep(0.15)

        assert status is not None
        assert status["status"] == "success"
        assert status["progress"] == 100
        stored = get_job(job_id)
        assert stored is not None
        assert stored["metadata"]["watermark"] == "AI 生成"
        result = client.get(status["result_url"])
        assert result.status_code == 200
        assert result.headers["content-type"] == "video/mp4"


def test_template_apply_respects_old_photo_animation_disable(monkeypatch, tmp_path):
    headers = {"X-App-Token": "test-token"}
    with _client(monkeypatch, tmp_path) as client:
        config = client.put(
            "/api/devices/d1/config",
            json={"enable_animate_old": False},
            headers=headers,
        )
        assert config.status_code == 200

        create = client.post(
            "/api/template/apply",
            json={
                "device_id": "d1",
                "template_id": "motion_old_photo",
                "text_index": 0,
                "image": _image_b64(),
            },
            headers=headers,
        )

        assert create.status_code == 400
        assert create.json()["detail"] == "老照片暂时不做动态"


def test_template_apply_respects_daily_budget(monkeypatch, tmp_path):
    headers = {"X-App-Token": "test-token"}
    with _client(monkeypatch, tmp_path) as client:
        config = client.put(
            "/api/devices/d1/config",
            json={"daily_budget_cny": 0.5},
            headers=headers,
        )
        assert config.status_code == 200

        create = client.post(
            "/api/template/apply",
            json={
                "device_id": "d1",
                "template_id": "midautumn_reunion",
                "text_index": 0,
                "image": _image_b64(),
            },
            headers=headers,
        )

        assert create.status_code == 429
        assert create.json()["detail"] == "今天的预算用完了,明天再试"
