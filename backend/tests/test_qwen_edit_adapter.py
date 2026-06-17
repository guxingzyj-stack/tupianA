import base64
from io import BytesIO

import pytest
from PIL import Image

from app.adapters.base import AdapterFailure
from app.adapters.qwen_edit_adapter import QwenEditAdapter


def _jpeg_bytes(color=(40, 90, 150)) -> bytes:
    buffer = BytesIO()
    Image.new("RGB", (32, 24), color).save(buffer, format="JPEG")
    return buffer.getvalue()


class _FakeResponse:
    def __init__(self, data):
        self._data = data

    def raise_for_status(self):
        return None

    def json(self):
        return self._data


class _FakeAsyncClient:
    last_request = None

    def __init__(self, *args, **kwargs):
        self.kwargs = kwargs

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, tb):
        return None

    async def post(self, path, *, data, files):
        _FakeAsyncClient.last_request = {
            "path": path,
            "data": data,
            "files": files,
            "headers": self.kwargs.get("headers"),
        }
        edited = base64.b64encode(_jpeg_bytes(color=(180, 120, 60))).decode("ascii")
        return _FakeResponse({"data": [{"b64_json": edited}]})


@pytest.mark.asyncio
async def test_qwen_edit_adapter_calls_image_edit_api_and_saves_jpeg(monkeypatch, tmp_path):
    monkeypatch.setattr("app.adapters.qwen_edit_adapter.httpx.AsyncClient", _FakeAsyncClient)
    source = tmp_path / "source.jpg"
    target = tmp_path / "edited.jpg"
    source.write_bytes(_jpeg_bytes())

    adapter = QwenEditAdapter(
        relay_base_url="https://relay.example.com/v1",
        relay_api_key="secret",
        image_edit_model="gpt-image-2",
    )

    result = await adapter.restore(source, target, instruction="自然修复老照片")

    assert result == target
    assert target.exists()
    with Image.open(target) as image:
        assert image.mode == "RGB"
        assert image.size == (32, 24)
    assert _FakeAsyncClient.last_request["path"] == "/images/edits"
    assert _FakeAsyncClient.last_request["data"]["model"] == "gpt-image-2"
    assert "自然修复老照片" in _FakeAsyncClient.last_request["data"]["prompt"]
    assert _FakeAsyncClient.last_request["headers"]["Authorization"] == "Bearer secret"


@pytest.mark.asyncio
async def test_qwen_edit_adapter_requires_model_credentials(tmp_path):
    source = tmp_path / "source.jpg"
    source.write_bytes(_jpeg_bytes())

    adapter = QwenEditAdapter(relay_base_url="", relay_api_key="")

    with pytest.raises(AdapterFailure):
        await adapter.restore(source, tmp_path / "edited.jpg", instruction="自然修复")
