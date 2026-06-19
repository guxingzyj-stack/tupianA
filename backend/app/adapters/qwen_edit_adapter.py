from __future__ import annotations

import base64
from io import BytesIO
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit, urlunsplit

import httpx
from PIL import Image, ImageOps

from app.adapters.base import AdapterFailure
from app.config import Settings, get_settings
from app.services.runtime_memory import release_memory


MAX_EDIT_IMAGE_DIMENSION = 1536
IMAGE_EDIT_PATH = "/images/edits"


class QwenEditAdapter:
    def __init__(
        self,
        settings: Settings | None = None,
        *,
        relay_base_url: str | None = None,
        relay_api_key: str | None = None,
        image_edit_model: str | None = None,
    ):
        self.settings = settings or get_settings()
        raw_base_url = relay_base_url or self.settings.relay_base_url
        self.relay_base_url, self.image_edit_path = _normalize_image_edit_endpoint(raw_base_url)
        self.relay_api_key = relay_api_key or self.settings.relay_api_key
        self.image_edit_model = image_edit_model or self.settings.image_edit_model

    async def restore(
        self,
        input_path: str | Path,
        output_path: str | Path,
        instruction: str,
    ) -> Path:
        if not self.relay_base_url or not self.relay_api_key:
            raise AdapterFailure("image edit model is not configured")

        prompt = _build_prompt(instruction)
        image_path = Path(input_path)
        try:
            image_bytes, mime_type = _prepare_image(image_path)
        except Exception as exc:
            raise AdapterFailure("input image cannot be prepared for edit model") from exc

        try:
            async with httpx.AsyncClient(
                base_url=self.relay_base_url,
                timeout=httpx.Timeout(120.0),
                headers={"Authorization": f"Bearer {self.relay_api_key}"},
            ) as client:
                response = await client.post(
                    self.image_edit_path,
                    data={
                        "model": self.image_edit_model,
                        "prompt": prompt,
                        "n": "1",
                    },
                    files={
                        "image[]": (image_path.name, image_bytes, mime_type),
                    },
                )
                response.raise_for_status()
                data = response.json()
        except Exception as exc:
            raise AdapterFailure("image edit request failed") from exc

        try:
            result_bytes = await _extract_result_bytes(data)
            return _save_result_image(result_bytes, output_path)
        except Exception as exc:
            raise AdapterFailure("image edit response is invalid") from exc
        finally:
            release_memory()


def _normalize_image_edit_endpoint(relay_base_url: str) -> tuple[str, str]:
    normalized = relay_base_url.strip().rstrip("/")
    if not normalized:
        return "", IMAGE_EDIT_PATH

    parsed = urlsplit(normalized)
    path = parsed.path.rstrip("/")
    if path.endswith(IMAGE_EDIT_PATH):
        base_path = path[: -len(IMAGE_EDIT_PATH)]
        normalized = urlunsplit((parsed.scheme, parsed.netloc, base_path, "", ""))

    return normalized.rstrip("/"), IMAGE_EDIT_PATH


def _build_prompt(instruction: str) -> str:
    detail = instruction.strip() or "自然修复并优化这张照片"
    return (
        "请对这张照片做自然、真实、商业级的修复和增强。"
        "保留人物身份、五官、构图、衣服、背景和照片年代感，不要改变主体内容，"
        "不要添加文字、水印、边框或虚构元素。"
        f"具体要求：{detail}。"
        "输出一张修复后的成品照片。"
    )


def _prepare_image(path: Path) -> tuple[bytes, str]:
    buffer = BytesIO()
    with Image.open(path) as image:
        prepared = ImageOps.exif_transpose(image).convert("RGB")
        prepared.thumbnail((MAX_EDIT_IMAGE_DIMENSION, MAX_EDIT_IMAGE_DIMENSION), Image.Resampling.LANCZOS)
        prepared.save(buffer, format="JPEG", quality=92, optimize=True)
        prepared.close()
    return buffer.getvalue(), "image/jpeg"


async def _extract_result_bytes(data: dict[str, Any]) -> bytes:
    items = data.get("data")
    if not isinstance(items, list) or not items:
        raise ValueError("missing image data")

    first = items[0]
    if not isinstance(first, dict):
        raise ValueError("invalid image item")

    b64_json = first.get("b64_json")
    if isinstance(b64_json, str) and b64_json:
        return base64.b64decode(b64_json)

    url = first.get("url")
    if isinstance(url, str) and url:
        async with httpx.AsyncClient(timeout=httpx.Timeout(60.0)) as client:
            response = await client.get(url)
            response.raise_for_status()
            return response.content

    raise ValueError("missing edited image")


def _save_result_image(image_bytes: bytes, output_path: str | Path) -> Path:
    target = Path(output_path)
    target.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(BytesIO(image_bytes)) as image:
        result = ImageOps.exif_transpose(image).convert("RGB")
        result.thumbnail((MAX_EDIT_IMAGE_DIMENSION, MAX_EDIT_IMAGE_DIMENSION), Image.Resampling.LANCZOS)
        result.save(target, format="JPEG", quality=92, optimize=True)
        result.close()
    return target
