from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont, ImageOps

from app.engine.local_video import create_local_motion_video


TONE_COLORS = {
    "warm": ((92, 55, 24), (255, 231, 190)),
    "moon": ((36, 52, 90), (236, 228, 194)),
    "green": ((31, 88, 54), (216, 244, 202)),
    "red": ((116, 28, 28), (255, 218, 190)),
    "gold": ((120, 78, 20), (255, 232, 160)),
    "blue": ((28, 68, 116), (212, 232, 255)),
    "pink": ((128, 54, 78), (255, 220, 231)),
    "natural": ((38, 48, 58), (236, 244, 246)),
    "nostalgia": ((92, 66, 42), (242, 220, 180)),
}


def create_local_template_video(
    image_path: str | Path,
    output_path: str | Path,
    *,
    template: dict,
    text: str,
) -> Path:
    prepared = _render_template_still(image_path, template=template, text=text)
    still_path = Path(output_path).with_suffix(".jpg")
    still_path.parent.mkdir(parents=True, exist_ok=True)
    prepared.save(still_path, format="JPEG", quality=94, optimize=True)
    return create_local_motion_video(
        still_path,
        output_path,
        motion=str(template.get("motion") or "slow_zoom"),
    )


def _render_template_still(
    image_path: str | Path,
    *,
    template: dict,
    text: str,
) -> Image.Image:
    with Image.open(image_path) as image:
        base = ImageOps.exif_transpose(image).convert("RGB")

    base.thumbnail((960, 960), Image.Resampling.LANCZOS)
    canvas = Image.new("RGB", _even_size(base.size), (244, 238, 226))
    canvas.paste(base.resize(canvas.size, Image.Resampling.LANCZOS))

    tone = str(template.get("tone") or "warm")
    dark, light = TONE_COLORS.get(tone, TONE_COLORS["warm"])
    canvas = _apply_tone(canvas, dark=dark, tone=tone)
    canvas = _draw_soft_frame(canvas, dark=dark, light=light)
    canvas = _draw_text_band(canvas, text=text, dark=dark, light=light)
    return canvas


def _even_size(size: tuple[int, int]) -> tuple[int, int]:
    width, height = size
    return (max(2, width - width % 2), max(2, height - height % 2))


def _apply_tone(image: Image.Image, *, dark: tuple[int, int, int], tone: str) -> Image.Image:
    overlay = Image.new("RGB", image.size, dark)
    strength = 0.08 if tone in {"natural", "blue", "green"} else 0.14
    toned = Image.blend(image, overlay, strength)
    toned = ImageEnhance.Contrast(toned).enhance(1.04)
    return ImageEnhance.Color(toned).enhance(1.06)


def _draw_soft_frame(
    image: Image.Image,
    *,
    dark: tuple[int, int, int],
    light: tuple[int, int, int],
) -> Image.Image:
    result = image.copy()
    draw = ImageDraw.Draw(result, "RGBA")
    width, height = result.size
    border = max(10, min(width, height) // 35)
    draw.rectangle((0, 0, width, height), outline=(*light, 210), width=border)
    draw.rectangle(
        (border // 2, border // 2, width - border // 2, height - border // 2),
        outline=(*dark, 120),
        width=max(2, border // 4),
    )
    return result


def _draw_text_band(
    image: Image.Image,
    *,
    text: str,
    dark: tuple[int, int, int],
    light: tuple[int, int, int],
) -> Image.Image:
    result = image.copy()
    draw = ImageDraw.Draw(result, "RGBA")
    width, height = result.size
    band_height = max(104, height // 5)
    top = height - band_height
    band = Image.new("RGBA", (width, band_height), (*dark, 198))
    band = band.filter(ImageFilter.GaussianBlur(radius=0.2))
    result.paste(band, (0, top), band)

    font_size = max(22, min(46, width // 13))
    font = _load_font(font_size)
    lines = _wrap_text(text, max_chars=max(7, width // font_size + 4))
    line_height = int(font_size * 1.34)
    total_height = line_height * len(lines)
    y = top + (band_height - total_height) // 2

    for line in lines:
        bbox = draw.textbbox((0, 0), line, font=font)
        text_width = bbox[2] - bbox[0]
        x = (width - text_width) // 2
        shadow_offset = max(2, font_size // 16)
        draw.text(
            (x + shadow_offset, y + shadow_offset),
            line,
            fill=(0, 0, 0, 130),
            font=font,
        )
        draw.text((x, y), line, fill=(*light, 255), font=font)
        y += line_height
    return result


def _load_font(size: int) -> ImageFont.ImageFont:
    candidates = (
        "C:/Windows/Fonts/msyh.ttc",
        "C:/Windows/Fonts/simhei.ttf",
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
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


def _wrap_text(text: str, *, max_chars: int) -> list[str]:
    chunks = [chunk for chunk in text.replace("　", " ").split(" ") if chunk]
    if not chunks:
        return [text]

    lines: list[str] = []
    current = ""
    for chunk in chunks:
        candidate = f"{current} {chunk}".strip()
        if len(candidate) <= max_chars:
            current = candidate
        else:
            if current:
                lines.append(current)
            current = chunk
    if current:
        lines.append(current)
    return lines[:2]
