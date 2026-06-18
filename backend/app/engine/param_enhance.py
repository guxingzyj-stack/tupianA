from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter, ImageOps

from app.engine.intent_mapper import Operation
from app.services.runtime_memory import release_memory


def apply_basic_enhancement(image_path: str | Path, output_path: str | Path) -> Path:
    operations = [
        Operation("brightness", 0.20),
        Operation("contrast", 0.12),
        Operation("saturation", 0.12),
        Operation("clarity", 0.14),
    ]
    return apply_operations(image_path, operations, output_path)


def apply_operations(
    image_path: str | Path,
    operations: list[Operation],
    output_path: str | Path,
) -> Path:
    image = _load_rgb(image_path)
    image = _normalize_tone(image)
    for operation in operations:
        image = _apply_operation(image, operation)
    target = Path(output_path)
    target.parent.mkdir(parents=True, exist_ok=True)
    try:
        image.save(target, format="JPEG", quality=92, optimize=True)
    finally:
        image.close()
        release_memory()
    return target


def image_stats(image_path: str | Path) -> dict[str, float]:
    image = _load_rgb(image_path)
    arr = np.asarray(image).astype(np.float32) / 255.0
    luma = 0.2126 * arr[..., 0] + 0.7152 * arr[..., 1] + 0.0722 * arr[..., 2]
    maxc = arr.max(axis=2)
    minc = arr.min(axis=2)
    saturation = np.where(maxc == 0, 0, (maxc - minc) / maxc)
    return {
        "brightness": float(luma.mean()),
        "saturation": float(saturation.mean()),
    }


def _load_rgb(path: str | Path) -> Image.Image:
    with Image.open(path) as image:
        return ImageOps.exif_transpose(image).convert("RGB")


def _normalize_tone(image: Image.Image) -> Image.Image:
    balanced = _gray_world_balance(image, strength=0.35)
    normalized = ImageOps.autocontrast(balanced, cutoff=0.5)
    return Image.blend(image, normalized, 0.55)


def _gray_world_balance(image: Image.Image, *, strength: float) -> Image.Image:
    arr = np.asarray(image).astype(np.float32) / 255.0
    means = arr.reshape(-1, 3).mean(axis=0)
    gray = float(means.mean())
    gains = gray / np.maximum(means, 1e-4)
    gains = 1.0 + (gains - 1.0) * strength
    return _array_to_image(arr * gains)


def _apply_operation(image: Image.Image, operation: Operation) -> Image.Image:
    if operation.type == "brightness":
        return _lift_shadows(image, operation.value)
    if operation.type == "saturation":
        return ImageEnhance.Color(image).enhance(1.0 + operation.value)
    if operation.type == "vibrance":
        return ImageEnhance.Color(image).enhance(1.0 + operation.value * 0.7)
    if operation.type == "contrast":
        return ImageEnhance.Contrast(image).enhance(1.0 + operation.value)
    if operation.type == "clarity":
        return image.filter(
            ImageFilter.UnsharpMask(
                radius=1.1,
                percent=80 + int(260 * operation.value),
                threshold=3,
            )
        )
    if operation.type == "warmth":
        return _adjust_warmth(image, operation.value)
    if operation.type == "sky_blue":
        return _boost_sky_blue(image, operation.value)
    if operation.type == "subject_boost":
        return _subject_boost(image, operation.value)
    if operation.type == "soft":
        return _soften(image, operation.value)
    return image


def _lift_shadows(image: Image.Image, value: float) -> Image.Image:
    arr = np.asarray(image).astype(np.float32) / 255.0
    luma = 0.2126 * arr[..., 0] + 0.7152 * arr[..., 1] + 0.0722 * arr[..., 2]
    shadow_weight = np.clip((0.72 - luma) / 0.72, 0, 1)[..., None]
    lift = value * 0.22 + value * 0.95 * shadow_weight
    lifted = arr + lift * (1.0 - arr)
    return _array_to_image(lifted)


def _adjust_warmth(image: Image.Image, value: float) -> Image.Image:
    arr = np.asarray(image).astype(np.float32) / 255.0
    arr[..., 0] = np.clip(arr[..., 0] + value * 0.35, 0, 1)
    arr[..., 2] = np.clip(arr[..., 2] - value * 0.25, 0, 1)
    return _array_to_image(arr)


def _boost_sky_blue(image: Image.Image, value: float) -> Image.Image:
    arr = np.asarray(image).astype(np.float32) / 255.0
    red, green, blue = arr[..., 0], arr[..., 1], arr[..., 2]
    mask = (blue > red * 1.08) & (blue > green * 0.92) & (blue > 0.28)
    arr[..., 2] = np.where(mask, np.clip(blue + value * (1 - blue), 0, 1), blue)
    arr[..., 1] = np.where(mask, np.clip(green + value * 0.10, 0, 1), green)
    return _array_to_image(arr)


def _subject_boost(image: Image.Image, value: float) -> Image.Image:
    arr = np.asarray(image).astype(np.float32) / 255.0
    luma = 0.2126 * arr[..., 0] + 0.7152 * arr[..., 1] + 0.0722 * arr[..., 2]
    mask = (luma < 0.58)[..., None]
    arr = np.where(mask, arr + value * 0.7 * (1 - arr), arr)
    boosted = _array_to_image(arr)
    return boosted.filter(ImageFilter.UnsharpMask(radius=1.0, percent=55, threshold=4))


def _soften(image: Image.Image, value: float) -> Image.Image:
    lower_contrast = ImageEnhance.Contrast(image).enhance(1.0 - min(value * 0.75, 0.35))
    lower_color = ImageEnhance.Color(lower_contrast).enhance(1.0 - min(value * 0.35, 0.18))
    blurred = lower_color.filter(ImageFilter.GaussianBlur(radius=0.85))
    softened = Image.blend(lower_color, blurred, 0.28)
    return ImageEnhance.Brightness(softened).enhance(1.0 + min(value * 0.18, 0.08))


def _array_to_image(arr: np.ndarray) -> Image.Image:
    return Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8), mode="RGB")
