from __future__ import annotations

from pathlib import Path
import sys


def main() -> None:
    target = Path(sys.argv[1] if len(sys.argv) > 1 else "test_images/cheetah.jpg")
    target.parent.mkdir(parents=True, exist_ok=True)
    width, height = 160, 96
    header = f"P6\n{width} {height}\n255\n".encode("ascii")
    pixels = bytearray()
    for y in range(height):
        for x in range(width):
            pixels.extend(
                (
                    min(255, 45 + x // 2),
                    min(255, 60 + y),
                    min(255, 95 + x // 3),
                )
            )
    target.write_bytes(header + bytes(pixels))
    print(f"Created sample image: {target}")


if __name__ == "__main__":
    main()

