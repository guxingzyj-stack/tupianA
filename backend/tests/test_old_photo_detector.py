from pathlib import Path
import warnings

from PIL import Image, ImageDraw, ImageFilter

from app.engine.old_photo_detector import is_old_photo, old_photo_options_for


def _make_old_photo(path: Path) -> None:
    image = Image.new("RGB", (220, 160), (166, 139, 88))
    draw = ImageDraw.Draw(image)
    for x in range(20, 200, 22):
        draw.line((x, 10, x + 18, 150), fill=(112, 96, 66), width=1)
    draw.line((112, 0, 115, 160), fill=(230, 220, 190), width=3)
    draw.ellipse((70, 42, 145, 126), outline=(92, 76, 54), width=4)
    image = image.filter(ImageFilter.GaussianBlur(radius=1.8))
    image.save(path, quality=90)


def _make_modern_photo(path: Path) -> None:
    image = Image.new("RGB", (220, 160), (40, 120, 210))
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 80, 220, 160), fill=(40, 180, 80))
    draw.ellipse((66, 32, 150, 130), fill=(235, 92, 80))
    draw.rectangle((20, 15, 95, 45), fill=(255, 230, 40))
    image.save(path, quality=95)


def test_old_photo_detector_hits_old_photo(tmp_path):
    path = tmp_path / "old.jpg"
    _make_old_photo(path)
    is_old, signals = is_old_photo(path)
    assert is_old
    assert len(signals) >= 2
    assert old_photo_options_for(path)[0]["name"] == "修旧如新"


def test_old_photo_detector_does_not_hit_modern_photo(tmp_path):
    path = tmp_path / "modern.jpg"
    _make_modern_photo(path)
    is_old, signals = is_old_photo(path)
    assert not is_old, signals


def test_old_photo_detector_handles_flat_color_without_warning(tmp_path):
    path = tmp_path / "flat.jpg"
    Image.new("RGB", (80, 60), (120, 120, 120)).save(path, quality=95)

    with warnings.catch_warnings():
        warnings.simplefilter("error", RuntimeWarning)
        is_old, signals = is_old_photo(path)

    assert isinstance(is_old, bool)
    assert isinstance(signals, list)
