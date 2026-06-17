from pathlib import Path

from PIL import Image, ImageDraw

from app.engine.document_scanner import correct_paper_photo


def test_correct_paper_photo_warps_detected_page(tmp_path):
    source = tmp_path / "paper.jpg"
    target = tmp_path / "corrected.jpg"
    image = Image.new("RGB", (420, 320), (42, 52, 55))
    draw = ImageDraw.Draw(image)
    polygon = [(84, 46), (342, 78), (318, 268), (58, 238)]
    draw.polygon(polygon, fill=(224, 208, 162))
    draw.rectangle((135, 128, 250, 176), outline=(118, 92, 64), width=4)
    image.save(source, quality=95)

    corrected_path, corrected = correct_paper_photo(source, target)

    assert corrected
    assert corrected_path == target
    assert target.exists()
    with Image.open(target) as corrected_image:
        assert corrected_image.width > 180
        assert corrected_image.height > 140


def test_correct_paper_photo_falls_back_without_page(tmp_path):
    source = tmp_path / "plain.jpg"
    target = tmp_path / "corrected.jpg"
    Image.new("RGB", (220, 160), (50, 120, 180)).save(source)

    corrected_path, corrected = correct_paper_photo(source, target)

    assert not corrected
    assert corrected_path == source
    assert not target.exists()

