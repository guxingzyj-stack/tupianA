import base64
from io import BytesIO

from fastapi.testclient import TestClient
from PIL import Image, ImageDraw, ImageFilter

from app.config import get_settings
from app.storage.db import get_job


def _image_b64() -> str:
    image = Image.new("RGB", (64, 48), (50, 80, 120))
    buffer = BytesIO()
    image.save(buffer, format="JPEG")
    return base64.b64encode(buffer.getvalue()).decode("ascii")


def _old_photo_b64() -> str:
    image = Image.new("RGB", (220, 160), (166, 139, 88))
    draw = ImageDraw.Draw(image)
    draw.line((112, 0, 115, 160), fill=(230, 220, 190), width=3)
    draw.ellipse((70, 42, 145, 126), outline=(92, 76, 54), width=4)
    image = image.filter(ImageFilter.GaussianBlur(radius=1.8))
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


def test_health_does_not_require_token(monkeypatch, tmp_path):
    client = _client(monkeypatch, tmp_path)
    response = client.get("/api/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"


def test_analyze_requires_token(monkeypatch, tmp_path):
    client = _client(monkeypatch, tmp_path)
    response = client.post("/api/analyze", json={"device_id": "d1", "image": _image_b64()})
    assert response.status_code == 401


def test_analyze_falls_back_without_relay_and_enhance(monkeypatch, tmp_path):
    client = _client(monkeypatch, tmp_path)
    headers = {"X-App-Token": "test-token"}
    analyze = client.post(
        "/api/analyze",
        json={"device_id": "d1", "image": _image_b64()},
        headers=headers,
    )
    assert analyze.status_code == 200
    body = analyze.json()
    assert [item["name"] for item in body["analysis"]["options"]] == ["更明亮", "更鲜艳", "更柔和"]
    assert body["is_old_photo"] is False

    base = client.get(body["base_image_url"])
    assert base.status_code == 200
    assert base.headers["content-type"] == "image/jpeg"

    enhance = client.post(
        "/api/enhance",
        json={"job_id": body["job_id"], "option_index": 0},
        headers=headers,
    )
    assert enhance.status_code == 200
    result = enhance.json()
    assert result["processing_ms"] >= 0

    image = client.get(result["result_image_url"])
    assert image.status_code == 200
    assert image.headers["content-type"] == "image/jpeg"


def test_analyze_accepts_shot_paper_flag(monkeypatch, tmp_path):
    client = _client(monkeypatch, tmp_path)
    headers = {"X-App-Token": "test-token"}
    analyze = client.post(
        "/api/analyze",
        json={
            "device_id": "d1",
            "image": _image_b64(),
            "is_shot_paper": True,
        },
        headers=headers,
    )
    assert analyze.status_code == 200
    body = analyze.json()
    assert body["job_id"]
    assert len(body["analysis"]["options"]) == 3


def test_analyze_replaces_options_for_old_photo(monkeypatch, tmp_path):
    client = _client(monkeypatch, tmp_path)
    headers = {"X-App-Token": "test-token"}
    analyze = client.post(
        "/api/analyze",
        json={"device_id": "d1", "image": _old_photo_b64()},
        headers=headers,
    )
    assert analyze.status_code == 200
    body = analyze.json()
    assert body["is_old_photo"] is True
    names = [item["name"] for item in body["analysis"]["options"]]
    assert names[0] == "修旧如新"
    assert names[1] in {"变成彩色", "颜色还原"}
    assert names[2] == "脸更清楚"


def test_enhance_old_photo_uses_restore_fallback(monkeypatch, tmp_path):
    client = _client(monkeypatch, tmp_path)
    headers = {"X-App-Token": "test-token"}
    analyze = client.post(
        "/api/analyze",
        json={"device_id": "d1", "image": _old_photo_b64()},
        headers=headers,
    )
    assert analyze.status_code == 200
    body = analyze.json()

    enhance = client.post(
        "/api/enhance",
        json={"job_id": body["job_id"], "option_index": 0},
        headers=headers,
    )
    assert enhance.status_code == 200
    result = enhance.json()

    image = client.get(result["result_image_url"])
    assert image.status_code == 200
    assert image.headers["content-type"] == "image/jpeg"

    job = get_job(body["job_id"])
    assert job is not None
    assert job["metadata"]["restore_processors"]["0"] == "local_fallback"


def test_device_config_api_masks_relay_key(monkeypatch, tmp_path):
    client = _client(monkeypatch, tmp_path)
    headers = {"X-App-Token": "test-token"}

    update = client.put(
        "/api/devices/d1/config",
        json={
            "nickname": "王奶奶",
            "daily_budget_cny": 8.5,
            "daily_video_limit": 0,
            "preferred_style": "更明亮",
            "enable_video": False,
            "enable_animate_old": True,
            "share_target": "家人群",
            "wechat_app_id": "wx123",
            "wechat_universal_link": "https://example.com/wechat/",
            "relay_base_url": "https://relay.example.com/v1",
            "relay_api_key": "secret-key",
            "ai_model": "claude-sonnet-4-6",
        },
        headers=headers,
    )
    assert update.status_code == 200
    body = update.json()
    assert body["nickname"] == "王奶奶"
    assert body["daily_video_limit"] == 0
    assert body["enable_video"] is False
    assert body["enable_animate_old"] is True
    assert body["share_target"] == "家人群"
    assert body["wechat_app_id"] == "wx123"
    assert body["wechat_universal_link"] == "https://example.com/wechat/"
    assert body["has_relay_api_key"] is True
    assert "secret-key" not in str(body)

    read = client.get("/api/devices/d1/config", headers=headers)
    assert read.status_code == 200
    assert read.json()["has_relay_api_key"] is True
    assert read.json()["wechat_app_id"] == "wx123"
    assert "relay_api_key" not in read.json()

    partial = client.put(
        "/api/devices/d1/config",
        json={"preferred_style": "更柔和"},
        headers=headers,
    )
    assert partial.status_code == 200
    partial_body = partial.json()
    assert partial_body["preferred_style"] == "更柔和"
    assert partial_body["share_target"] == "家人群"
    assert partial_body["wechat_app_id"] == "wx123"
    assert partial_body["wechat_universal_link"] == "https://example.com/wechat/"
    assert partial_body["relay_base_url"] == "https://relay.example.com/v1"
    assert partial_body["ai_model"] == "claude-sonnet-4-6"
    assert partial_body["has_relay_api_key"] is True


def test_video_respects_device_config_disable(monkeypatch, tmp_path):
    client = _client(monkeypatch, tmp_path)
    headers = {"X-App-Token": "test-token"}
    client.put(
        "/api/devices/d1/config",
        json={"enable_video": False},
        headers=headers,
    )
    analyze = client.post(
        "/api/analyze",
        json={"device_id": "d1", "image": _image_b64()},
        headers=headers,
    )
    assert analyze.status_code == 200

    video = client.post(
        "/api/video",
        json={
            "device_id": "d1",
            "image_url": analyze.json()["base_image_url"],
            "motion": "slow_zoom",
        },
        headers=headers,
    )
    assert video.status_code == 400
    assert video.json()["detail"] == "视频功能暂时关闭"


def test_analyze_respects_daily_budget_when_relay_is_configured(monkeypatch, tmp_path):
    client = _client(monkeypatch, tmp_path)
    headers = {"X-App-Token": "test-token"}
    config = client.put(
        "/api/devices/d1/config",
        json={
            "daily_budget_cny": 0,
            "relay_base_url": "https://relay.example.com/v1",
            "relay_api_key": "secret-key",
        },
        headers=headers,
    )
    assert config.status_code == 200

    analyze = client.post(
        "/api/analyze",
        json={"device_id": "d1", "image": _image_b64()},
        headers=headers,
    )

    assert analyze.status_code == 429
    assert analyze.json()["detail"] == "今天的预算用完了,明天再试"


def test_old_photo_enhance_respects_daily_budget(monkeypatch, tmp_path):
    client = _client(monkeypatch, tmp_path)
    headers = {"X-App-Token": "test-token"}
    config = client.put(
        "/api/devices/d1/config",
        json={"daily_budget_cny": 0.1},
        headers=headers,
    )
    assert config.status_code == 200
    analyze = client.post(
        "/api/analyze",
        json={"device_id": "d1", "image": _old_photo_b64()},
        headers=headers,
    )
    assert analyze.status_code == 200

    enhance = client.post(
        "/api/enhance",
        json={"job_id": analyze.json()["job_id"], "option_index": 0},
        headers=headers,
    )

    assert enhance.status_code == 429
    assert enhance.json()["detail"] == "今天的预算用完了,明天再试"
