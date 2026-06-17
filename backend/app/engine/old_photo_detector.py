from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter, ImageOps


OLD_PHOTO_OPTIONS = [
    {
        "name": "修旧如新",
        "intent": "去模糊 + 去划痕 + 褪色还原,保持黑白",
    },
    {
        "name": "变成彩色",
        "intent": "去模糊 + 去划痕 + 黑白上色",
    },
    {
        "name": "脸更清楚",
        "intent": "GFPGAN 人脸专修 + 整体增强",
    },
]

COLOR_OLD_PHOTO_OPTIONS = [
    {
        "name": "修旧如新",
        "intent": "去模糊 + 去划痕 + 褪色还原",
    },
    {
        "name": "颜色还原",
        "intent": "去模糊 + 去划痕 + 颜色还原",
    },
    {
        "name": "脸更清楚",
        "intent": "GFPGAN 人脸专修 + 整体增强",
    },
]

_SCENE_KEYWORDS = ("老照片", "旧照", "翻拍", "黑白", "纸质", "泛黄")


def is_old_photo(
    image_path: str | Path,
    claude_scene: str = "",
) -> tuple[bool, list[str]]:
    image = _load_small_rgb(image_path)
    arr = np.asarray(image).astype(np.float32) / 255.0
    hsv = _rgb_to_hsv(arr)
    saturation = hsv[..., 1]
    hue = hsv[..., 0]
    value = hsv[..., 2]
    gray = _to_gray(arr)

    signals: list[str] = []

    if float(saturation.mean()) < 0.20:
        signals.append("低饱和")
    if _has_paper_noise(gray):
        signals.append("纸面噪点")
    if _has_linear_scratches(gray):
        signals.append("折痕划痕")
    if any(keyword in claude_scene for keyword in _SCENE_KEYWORDS):
        signals.append("场景提示")
    if _is_yellow_brown(hue, saturation, value):
        signals.append("黄褐色调")
    if _laplacian_variance(gray) < 0.0012:
        signals.append("锐度低")

    return len(signals) >= 2, signals


def old_photo_options_for(image_path: str | Path) -> list[dict[str, str]]:
    image = _load_small_rgb(image_path)
    arr = np.asarray(image).astype(np.float32) / 255.0
    hsv = _rgb_to_hsv(arr)
    if float(hsv[..., 1].mean()) > 0.16:
        return [dict(option) for option in COLOR_OLD_PHOTO_OPTIONS]
    return [dict(option) for option in OLD_PHOTO_OPTIONS]


def _load_small_rgb(path: str | Path) -> Image.Image:
    with Image.open(path) as image:
        rgb = ImageOps.exif_transpose(image).convert("RGB")
        rgb.thumbnail((720, 720))
        return rgb.copy()


def _to_gray(arr: np.ndarray) -> np.ndarray:
    return 0.2126 * arr[..., 0] + 0.7152 * arr[..., 1] + 0.0722 * arr[..., 2]


def _rgb_to_hsv(arr: np.ndarray) -> np.ndarray:
    red, green, blue = arr[..., 0], arr[..., 1], arr[..., 2]
    maxc = arr.max(axis=2)
    minc = arr.min(axis=2)
    delta = maxc - minc

    hue = np.zeros_like(maxc)
    nonzero = delta > 1e-6
    red_max = (maxc == red) & nonzero
    green_max = (maxc == green) & nonzero
    blue_max = (maxc == blue) & nonzero
    hue = np.where(red_max, ((green - blue) / delta) % 6, hue)
    hue = np.where(green_max, ((blue - red) / delta) + 2, hue)
    hue = np.where(blue_max, ((red - green) / delta) + 4, hue)
    hue = hue / 6.0

    saturation = np.where(maxc <= 1e-6, 0, delta / maxc)
    return np.stack([hue, saturation, maxc], axis=2)


def _has_paper_noise(gray: np.ndarray) -> bool:
    smooth = np.asarray(
        Image.fromarray((gray * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(radius=2.0)),
    ).astype(np.float32) / 255.0
    residual = gray - smooth
    variance = float(np.var(residual))
    return 0.00025 < variance < 0.006


def _has_linear_scratches(gray: np.ndarray) -> bool:
    gy, gx = np.gradient(gray)
    magnitude = np.sqrt(gx * gx + gy * gy)
    strong = magnitude > max(0.10, float(magnitude.mean() + magnitude.std() * 1.8))
    vertical_density = _long_line_density(strong, axis=0)
    horizontal_density = _long_line_density(strong, axis=1)
    return vertical_density > 0.018 or horizontal_density > 0.018


def _long_line_density(mask: np.ndarray, axis: int) -> float:
    runs = 0
    total = mask.size
    view = mask.T if axis == 0 else mask
    for row in view:
        current = 0
        for value in row:
            if value:
                current += 1
            else:
                if current >= 18:
                    runs += current
                current = 0
        if current >= 18:
            runs += current
    return runs / total


def _is_yellow_brown(hue: np.ndarray, saturation: np.ndarray, value: np.ndarray) -> bool:
    yellow_brown = (hue > 0.07) & (hue < 0.18) & (saturation > 0.08) & (value > 0.16)
    return float(yellow_brown.mean()) > 0.45


def _laplacian_variance(gray: np.ndarray) -> float:
    center = gray[1:-1, 1:-1] * -4
    lap = center + gray[:-2, 1:-1] + gray[2:, 1:-1] + gray[1:-1, :-2] + gray[1:-1, 2:]
    return float(np.var(lap))

