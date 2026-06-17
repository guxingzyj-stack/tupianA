from types import SimpleNamespace

from app.config import get_settings
from app.storage.files import public_url_for_path


def test_public_url_for_zeabur_request_uses_https(monkeypatch, tmp_path):
    file_base = tmp_path / "files"
    target = file_base / "outputs" / "device" / "job" / "base.jpg"
    target.parent.mkdir(parents=True)
    target.write_bytes(b"jpg")
    monkeypatch.setenv("FILE_BASE", str(file_base))
    monkeypatch.setenv("PUBLIC_BASE_URL", "")
    get_settings.cache_clear()

    request = SimpleNamespace(base_url="http://tupiana.zeabur.app/")

    assert (
        public_url_for_path(target, request)
        == "https://tupiana.zeabur.app/files/outputs/device/job/base.jpg"
    )


def test_public_url_prefers_explicit_public_base_url(monkeypatch, tmp_path):
    file_base = tmp_path / "files"
    target = file_base / "outputs" / "device" / "job" / "base.jpg"
    target.parent.mkdir(parents=True)
    target.write_bytes(b"jpg")
    monkeypatch.setenv("FILE_BASE", str(file_base))
    monkeypatch.setenv("PUBLIC_BASE_URL", "https://photos.example.com")
    get_settings.cache_clear()

    request = SimpleNamespace(base_url="http://internal.local/")

    assert (
        public_url_for_path(target, request)
        == "https://photos.example.com/files/outputs/device/job/base.jpg"
    )
