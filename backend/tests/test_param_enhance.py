from pathlib import Path

from PIL import Image, ImageChops, ImageStat

from app.engine.intent_mapper import parse_intent
from app.engine.param_enhance import apply_operations, image_stats


def _sample_image(path: Path) -> None:
    image = Image.new("RGB", (96, 64))
    pixels = image.load()
    for x in range(image.width):
        for y in range(image.height):
            pixels[x, y] = (40 + x, 35 + y, 80 + x // 3)
    image.save(path)


def test_parse_intent_covers_prd_keywords():
    keywords = [
        "整体提亮",
        "更亮",
        "鲜艳",
        "色彩增强",
        "通透",
        "对比",
        "暖色",
        "天空更蓝",
        "主体更清楚",
        "暖色草原",
        "纪录片感",
        "柔和",
    ]
    for keyword in keywords:
        assert parse_intent(keyword)


def test_soft_intent_does_not_raise_contrast():
    operations = parse_intent("降低对比、柔光化")
    assert [operation.type for operation in operations] == ["soft", "brightness"]


def test_brightness_intent_increases_brightness(tmp_path):
    source = tmp_path / "source.jpg"
    target = tmp_path / "bright.jpg"
    _sample_image(source)
    before = image_stats(source)
    apply_operations(source, parse_intent("整体提亮"), target)
    after = image_stats(target)
    assert target.exists()
    assert after["brightness"] > before["brightness"]
    assert _mean_abs_diff(source, target) > 12


def test_saturation_intent_increases_saturation(tmp_path):
    source = tmp_path / "source.jpg"
    target = tmp_path / "color.jpg"
    _sample_image(source)
    before = image_stats(source)
    apply_operations(source, parse_intent("色彩增强"), target)
    after = image_stats(target)
    assert target.exists()
    assert after["saturation"] > before["saturation"]
    assert _mean_abs_diff(source, target) > 10


def test_default_enhancement_is_visibly_different(tmp_path):
    source = tmp_path / "source.jpg"
    target = tmp_path / "default.jpg"
    _sample_image(source)

    apply_operations(source, parse_intent(""), target)

    assert _mean_abs_diff(source, target) > 10


def _mean_abs_diff(before_path: Path, after_path: Path) -> float:
    with Image.open(before_path) as before, Image.open(after_path) as after:
        diff = ImageChops.difference(before.convert("RGB"), after.convert("RGB"))
        return sum(ImageStat.Stat(diff).mean) / 3
