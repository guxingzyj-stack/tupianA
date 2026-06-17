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
    base = ImageOps.autocontrast(base, cutoff=0.5)
    cleaned = base.filter(ImageFilter.MedianFilter(size=3))
    blended = Image.blend(base.convert("RGB"), cleaned.convert("RGB"), 0.34)
    lifted = _lift_old_photo_shadows(blended, amount=0.16)
    restored = ImageEnhance.Contrast(lifted).enhance(1.20)
    restored = ImageEnhance.Brightness(restored).enhance(1.04)
    return restored.filter(ImageFilter.UnsharpMask(radius=1.1, percent=145, threshold=3))


def _colorize_black_white(image: Image.Image) -> Image.Image:
    gray = ImageOps.autocontrast(ImageOps.grayscale(image), cutoff=0.5)
    colorized = ImageOps.colorize(
        gray,
        black=(28, 26, 24),
        mid=(176, 132, 88),
        white=(248, 226, 190),
    )
    colorized = ImageEnhance.Color(colorized).enhance(1.26)
    colorized = ImageEnhance.Contrast(colorized).enhance(1.12)
    return colorized.filter(ImageFilter.UnsharpMask(radius=1.1, percent=110, threshold=4))


def _restore_faded_color(image: Image.Image) -> Image.Image:
    result = _gray_world_balance(image, strength=0.55)
    result = ImageOps.autocontrast(result, cutoff=0.5)
    result = _lift_old_photo_shadows(result, amount=0.10)
    result = ImageEnhance.Color(result).enhance(1.42)
    result = ImageEnhance.Contrast(result).enhance(1.16)
    return result.filter(ImageFilter.UnsharpMask(radius=1.0, percent=115, threshold=4))


def _face_clarity_fallback(image: Image.Image) -> Image.Image:
    balanced = _gray_world_balance(image, strength=0.35)
    arr = np.asarray(ImageOps.autocontrast(balanced, cutoff=0.5)).astype(np.float32) / 255.0
    luma = 0.2126 * arr[..., 0] + 0.7152 * arr[..., 1] + 0.0722 * arr[..., 2]
    shadow = (luma < 0.55)[..., None]
    arr = np.where(shadow, arr + 0.18 * (1.0 - arr), arr)
    lifted = Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), mode="RGB")
    lifted = ImageEnhance.Contrast(lifted).enhance(1.10)
    return lifted.filter(ImageFilter.UnsharpMask(radius=1.3, percent=155, threshold=3))


def _gray_world_balance(image: Image.Image, *, strength: float) -> Image.Image:
    arr = np.asarray(image).astype(np.float32) / 255.0
    means = arr.reshape(-1, 3).mean(axis=0)
    gray = float(means.mean())
    gains = gray / np.maximum(means, 1e-4)
    gains = 1.0 + (gains - 1.0) * strength
    return Image.fromarray((np.clip(arr * gains, 0, 1) * 255).astype(np.uint8), mode="RGB")


def _lift_old_photo_shadows(image: Image.Image, *, amount: float) -> Image.Image:
    arr = np.asarray(image).astype(np.float32) / 255.0
    luma = 0.2126 * arr[..., 0] + 0.7152 * arr[..., 1] + 0.0722 * arr[..., 2]
    shadow_weight = np.clip((0.76 - luma) / 0.76, 0, 1)[..., None]
    lifted = arr + amount * shadow_weight * (1.0 - arr)
    return Image.fromarray((np.clip(lifted, 0, 1) * 255).astype(np.uint8), mode="RGB")
