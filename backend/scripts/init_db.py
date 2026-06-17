from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from app.config import get_settings  # noqa: E402
from app.storage.db import init_db  # noqa: E402


def main() -> None:
    settings = get_settings()
    init_db(settings.db_path)
    print(f"SQLite database is ready: {settings.db_path}")


if __name__ == "__main__":
    main()

