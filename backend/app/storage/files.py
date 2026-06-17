from __future__ import annotations

import base64
import re
from io import BytesIO
from pathlib import Path
from urllib.parse import quote
from urllib.parse import unquote
from urllib.parse import urlparse

from fastapi import Request
from PIL import Image, ImageOps

from app.config import get_settings


_SAFE_SEGMENT_RE = re.compile(r"[^A-Za-z0-9_.-]+")


def sanitize_segment(value: str) -> str:
    cleaned = _SAFE_SEGMENT_RE.sub("_", value).strip("._")
    return cleaned or "unknown"


def file_base(file_base: str | None = None) -> Path:
    base = Path(file_base or get_settings().file_base)
    base.mkdir(parents=True, exist_ok=True)
    return base


def _strip_data_url(image_b64: str) -> str:
    if "," in image_b64 and image_b64.lstrip().startswith("data:"):
        return image_b64.split(",", 1)[1]
    return image_b64


def decode_image_b64(image_b64: str) -> Image.Image:
    try:
        raw = base64.b64decode(_strip_data_url(image_b64), validate=True)
        with Image.open(BytesIO(raw)) as image:
            return ImageOps.exif_transpose(image).convert("RGB")
    except Exception as exc:
        raise ValueError("图片格式不对") from exc


def save_base64_image(
    *,
    device_id: str,
    job_id: str,
    image_b64: str,
    file_base_path: str | None = None,
) -> Path:
    image = decode_image_b64(image_b64)
    base = file_base(file_base_path)
    safe_device = sanitize_segment(device_id)
    safe_job = sanitize_segment(job_id)
    target = base / "inputs" / safe_device / f"{safe_job}.jpg"
    target.parent.mkdir(parents=True, exist_ok=True)
    image.save(target, format="JPEG", quality=94, optimize=True)
    return target


def output_dir(device_id: str, job_id: str, file_base_path: str | None = None) -> Path:
    base = file_base(file_base_path)
    target = base / "outputs" / sanitize_segment(device_id) / sanitize_segment(job_id)
    target.mkdir(parents=True, exist_ok=True)
    return target


def video_path(device_id: str, job_id: str, file_base_path: str | None = None) -> Path:
    base = file_base(file_base_path)
    target = base / "videos" / sanitize_segment(device_id) / f"{sanitize_segment(job_id)}.mp4"
    target.parent.mkdir(parents=True, exist_ok=True)
    return target


def path_from_public_url(url_or_path: str | Path) -> Path:
    raw = str(url_or_path)
    parsed_path = urlparse(raw).path if "://" in raw else raw
    marker = "/files/"
    if marker in parsed_path:
        relative = unquote(parsed_path.split(marker, 1)[1])
        target = (file_base() / relative).resolve()
    else:
        target = Path(raw).resolve()

    base = file_base().resolve()
    try:
        target.relative_to(base)
    except ValueError as exc:
        raise ValueError("这张照片暂时找不到") from exc
    return target


def public_url_for_path(path: str | Path, request: Request | None = None) -> str:
    settings = get_settings()
    target = Path(path).resolve()
    base = settings.file_base_dir.resolve()
    relative = target.relative_to(base).as_posix()
    encoded = quote(relative, safe="/")
    if settings.public_base_url:
        return f"{settings.public_base_url.rstrip('/')}/files/{encoded}"
    if request is not None:
        return f"{str(request.base_url).rstrip('/')}/files/{encoded}"
    return f"/files/{encoded}"
