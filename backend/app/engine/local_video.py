from __future__ import annotations

import math
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageOps


ALLOWED_MOTIONS = {"slow_zoom", "env_breeze", "subtle_human"}
MOTION_LABELS = {
    "slow_zoom": "缓慢推镜",
    "env_breeze": "环境微动",
    "subtle_human": "人物轻动",
}
WATERMARK_TEXT = "AI 生成"


def create_local_motion_video(
    image_path: str | Path,
    output_path: str | Path,
    *,
    motion: str,
    duration_seconds: int = 8,
    fps: int = 12,
) -> Path:
    if motion not in ALLOWED_MOTIONS:
        raise ValueError("这个动态方式不存在")

    source = _load_frame(image_path)
    width, height = source.size
    target = Path(output_path)
    target.parent.mkdir(parents=True, exist_ok=True)

    writer = cv2.VideoWriter(
        str(target),
        cv2.VideoWriter_fourcc(*"mp4v"),
        fps,
        (width, height),
    )
    if not writer.isOpened():
        raise RuntimeError("视频暂时做不了")

    try:
        frame_count = duration_seconds * fps
        for frame_index in range(frame_count):
            progress = frame_index / max(frame_count - 1, 1)
            frame = _render_frame(source, motion=motion, progress=progress)
            writer.write(cv2.cvtColor(np.asarray(frame), cv2.COLOR_RGB2BGR))
    finally:
        writer.release()

    return target


def _load_frame(path: str | Path) -> Image.Image:
    with Image.open(path) as image:
        image = ImageOps.exif_transpose(image).convert("RGB")
        image.thumbnail((720, 720), Image.Resampling.LANCZOS)
        width, height = image.size
        even_size = (width - width % 2, height - height % 2)
        if even_size != image.size:
            image = image.resize(even_size, Image.Resampling.LANCZOS)
        return image.copy()


def _render_frame(source: Image.Image, *, motion: str, progress: float) -> Image.Image:
    if motion == "slow_zoom":
        scale = 1.0 + progress * 0.10
        dx = 0
        dy = 0
    elif motion == "env_breeze":
        scale = 1.04
        dx = int(math.sin(progress * math.tau * 1.25) * source.width * 0.018)
        dy = int(math.sin(progress * math.tau * 0.80) * source.height * 0.010)
    else:
        scale = 1.0 + progress * 0.04
        dx = 0
        dy = int(math.sin(progress * math.tau) * source.height * 0.006)

    frame = _crop_zoom(source, scale=scale, dx=dx, dy=dy)
    return _draw_ai_watermark(frame)


def _crop_zoom(source: Image.Image, *, scale: float, dx: int, dy: int) -> Image.Image:
    width, height = source.size
    scaled = source.resize(
        (max(width, int(width * scale)), max(height, int(height * scale))),
        Image.Resampling.LANCZOS,
    )
    left = (scaled.width - width) // 2 + dx
    top = (scaled.height - height) // 2 + dy
    left = max(0, min(left, scaled.width - width))
    top = max(0, min(top, scaled.height - height))
    return scaled.crop((left, top, left + width, top + height))


def _draw_ai_watermark(frame: Image.Image) -> Image.Image:
    result = frame.copy()
    draw = ImageDraw.Draw(result, "RGBA")
    font_size = max(16, min(24, result.width // 24))
    font = _load_font(font_size)
    padding = max(10, font_size // 2)
    bbox = draw.textbbox((0, 0), WATERMARK_TEXT, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]
    box = (
        result.width - text_width - padding * 2,
        result.height - text_height - padding * 2,
        result.width,
        result.height,
    )
    draw.rounded_rectangle(box, radius=6, fill=(0, 0, 0, 140))
    draw.text(
        (box[0] + padding, box[1] + padding - 1),
        WATERMARK_TEXT,
        fill=(255, 255, 255, 255),
        font=font,
    )
    return result


def _load_font(size: int) -> ImageFont.ImageFont:
    candidates = (
        "C:/Windows/Fonts/msyh.ttc",
        "C:/Windows/Fonts/simhei.ttf",
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc",
        "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
        "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "DejaVuSans.ttf",
    )
    for candidate in candidates:
        try:
            return ImageFont.truetype(candidate, size=size)
        except OSError:
            continue
    return ImageFont.load_default()
