from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter, ImageOps


OLD_PHOTO_INTENT_KEYWORDS = (
    "去模糊",
    "去划痕",
    "褪色还原",
    "黑白上色",
    "GFPGAN",
    "人脸专修",
    "脸更清楚",
    "颜色还原",
)


def is_old_photo_intent(intent: str, option_name: str = "") -> bool:
    text = f"{intent} {option_name}"
    return any(keyword in text for keyword in OLD_PHOTO_INTENT_KEYWORDS)


def apply_local_old_photo_restore(
    input_path: str | Path,
    output_path: str | Path,
    *,
    intent: str,
    option_name: str,
) -> Path:
    image = _load_rgb(input_path)
    if "黑白上色" in intent or option_name == "变成彩色":
        result = _colorize_black_white(image)
    elif "颜色还原" in intent or option_name == "颜色还原":
        result = _restore_faded_color(image)
    elif "人脸专修" in intent or "脸更清楚" in option_name:
        result = _face_clarity_fallback(image)
    else:
        result = _repair_old_photo(image, keep_black_white="保持黑白" in intent)

    target = Path(output_path)
    target.parent.mkdir(parents=True, exist_ok=True)
    result.save(target, format="JPEG", quality=94, optimize=True)
    return target


def _load_rgb(path: str | Path) -> Image.Image:
    with Image.open(path) as image:
        return ImageOps.exif_transpose(image).convert("RGB")


def _repair_old_photo(image: Image.Image, *, keep_black_white: bool) -> Image.Image:
    base = ImageOps.grayscale(image) if keep_black_white else image
    base = ImageOps.autocontrast(base, cutoff=1)
    cleaned = base.filter(ImageFilter.MedianFilter(size=3))
    blended = Image.blend(base.convert("RGB"), cleaned.convert("RGB"), 0.26)
    blended = ImageEnhance.Contrast(blended).enhance(1.08)
    return blended.filter(ImageFilter.UnsharpMask(radius=1.2, percent=90, threshold=4))


def _colorize_black_white(image: Image.Image) -> Image.Image:
    gray = ImageOps.autocontrast(ImageOps.grayscale(image), cutoff=1)
    colorized = ImageOps.colorize(
        gray,
        black=(34, 30, 28),
        mid=(156, 125, 92),
        white=(238, 220, 188),
    )
    colorized = ImageEnhance.Color(colorized).enhance(1.10)
    return colorized.filter(ImageFilter.UnsharpMask(radius=1.1, percent=70, threshold=4))


def _restore_faded_color(image: Image.Image) -> Image.Image:
    result = ImageOps.autocontrast(image, cutoff=1)
    result = ImageEnhance.Color(result).enhance(1.22)
    result = ImageEnhance.Contrast(result).enhance(1.08)
    return result.filter(ImageFilter.UnsharpMask(radius=1.0, percent=65, threshold=4))


def _face_clarity_fallback(image: Image.Image) -> Image.Image:
    arr = np.asarray(ImageOps.autocontrast(image, cutoff=1)).astype(np.float32) / 255.0
    luma = 0.2126 * arr[..., 0] + 0.7152 * arr[..., 1] + 0.0722 * arr[..., 2]
    shadow = (luma < 0.55)[..., None]
    arr = np.where(shadow, arr + 0.10 * (1.0 - arr), arr)
    lifted = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), mode="RGB")
    return lifted.filter(ImageFilter.UnsharpMask(radius=1.4, percent=115, threshold=3))
