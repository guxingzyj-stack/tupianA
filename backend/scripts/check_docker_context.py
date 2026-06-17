from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DOCKERFILE = ROOT / "Dockerfile"
DOCKERIGNORE = ROOT / ".dockerignore"


REQUIRED_DOCKERFILE_SNIPPETS = [
    "FROM python:3.11-slim",
    "fonts-noto-cjk",
    "COPY requirements.txt .",
    "pip install -r requirements.txt",
    "COPY . .",
    'CMD ["uvicorn", "app.main:app"',
]

REQUIRED_IGNORES = [
    ".env",
    "data/",
    "smoke_output/",
    "test_images/",
    "deployment_evidence.json",
    ".pytest_cache/",
    "__pycache__/",
    "tests/",
]


def main() -> None:
    errors: list[str] = []

    dockerfile = _read(DOCKERFILE, errors)
    dockerignore = _read(DOCKERIGNORE, errors)

    for snippet in REQUIRED_DOCKERFILE_SNIPPETS:
        if snippet not in dockerfile:
            errors.append(f"Dockerfile is missing expected snippet: {snippet}")

    ignored = {
        line.strip()
        for line in dockerignore.splitlines()
        if line.strip() and not line.strip().startswith("#")
    }
    for pattern in REQUIRED_IGNORES:
        if pattern not in ignored:
            errors.append(f".dockerignore is missing: {pattern}")

    if errors:
        print("Docker context check failed:")
        for error in errors:
            print(f"  - {error}")
        raise SystemExit(1)

    print("Docker context check passed.")


def _read(path: Path, errors: list[str]) -> str:
    if not path.exists():
        errors.append(f"Missing file: {path.name}")
        return ""
    return path.read_text(encoding="utf-8")


if __name__ == "__main__":
    main()
