from pathlib import Path

from PIL import Image, ImageChops

from app.engine.old_photo_restore import apply_local_old_photo_restore, is_old_photo_intent


def _sample_old_photo(path: Path) -> None:
    image = Image.new("RGB", (120, 90), (158, 132, 88))
    pixels = image.load()
    for x in range(image.width):
        for y in range(image.height):
            if (x + y) % 17 == 0:
                pixels[x, y] = (218, 204, 166)
    image.save(path, quality=90)


def test_old_photo_intent_matches_restore_keywords():
    assert is_old_photo_intent("去模糊、去划痕，保持黑白")
    assert is_old_photo_intent("", "脸更清楚")


def test_local_old_photo_restore_writes_changed_jpeg(tmp_path):
    source = tmp_path / "old.jpg"
    target = tmp_path / "restored.jpg"
    _sample_old_photo(source)

    result = apply_local_old_photo_restore(
        source,
        target,
        intent="去模糊、去划痕，保持黑白",
        option_name="修旧如新",
    )

    assert result == target
    assert target.exists()
    with Image.open(source) as before, Image.open(target) as after:
        assert after.mode == "RGB"
        assert after.size == before.size
        assert ImageChops.difference(before.convert("RGB"), after).getbbox() is not None
