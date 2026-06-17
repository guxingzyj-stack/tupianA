from __future__ import annotations

from pathlib import Path

import numpy as np


def correct_paper_photo(
    input_path: str | Path,
    output_path: str | Path,
) -> tuple[Path, bool]:
    try:
        import cv2
    except Exception:
        return Path(input_path), False

    source = Path(input_path)
    target = Path(output_path)
    image = cv2.imread(str(source))
    if image is None:
        return source, False

    original = image.copy()
    ratio = image.shape[0] / 720.0 if image.shape[0] > 720 else 1.0
    resized = image if ratio == 1.0 else cv2.resize(image, (int(image.shape[1] / ratio), 720))

    gray = cv2.cvtColor(resized, cv2.COLOR_BGR2GRAY)
    gray = cv2.GaussianBlur(gray, (5, 5), 0)
    edges = cv2.Canny(gray, 55, 160)
    edges = cv2.dilate(edges, np.ones((3, 3), np.uint8), iterations=1)

    contours, _ = cv2.findContours(edges, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    contours = sorted(contours, key=cv2.contourArea, reverse=True)[:8]

    page = None
    image_area = resized.shape[0] * resized.shape[1]
    for contour in contours:
        perimeter = cv2.arcLength(contour, True)
        approx = cv2.approxPolyDP(contour, 0.02 * perimeter, True)
        if len(approx) != 4:
            continue
        if cv2.contourArea(approx) < image_area * 0.20:
            continue
        page = approx.reshape(4, 2).astype("float32")
        break

    if page is None:
        return source, False

    page *= ratio
    ordered = _order_points(page)
    width_a = np.linalg.norm(ordered[2] - ordered[3])
    width_b = np.linalg.norm(ordered[1] - ordered[0])
    height_a = np.linalg.norm(ordered[1] - ordered[2])
    height_b = np.linalg.norm(ordered[0] - ordered[3])
    max_width = int(max(width_a, width_b))
    max_height = int(max(height_a, height_b))
    if max_width < 80 or max_height < 80:
        return source, False

    destination = np.array(
        [
            [0, 0],
            [max_width - 1, 0],
            [max_width - 1, max_height - 1],
            [0, max_height - 1],
        ],
        dtype="float32",
    )
    matrix = cv2.getPerspectiveTransform(ordered, destination)
    warped = cv2.warpPerspective(original, matrix, (max_width, max_height))

    target.parent.mkdir(parents=True, exist_ok=True)
    ok = cv2.imwrite(str(target), warped, [int(cv2.IMWRITE_JPEG_QUALITY), 94])
    if not ok:
        return source, False
    return target, True


def _order_points(points: np.ndarray) -> np.ndarray:
    rect = np.zeros((4, 2), dtype="float32")
    sums = points.sum(axis=1)
    rect[0] = points[np.argmin(sums)]
    rect[2] = points[np.argmax(sums)]
    diffs = np.diff(points, axis=1)
    rect[1] = points[np.argmin(diffs)]
    rect[3] = points[np.argmax(diffs)]
    return rect

