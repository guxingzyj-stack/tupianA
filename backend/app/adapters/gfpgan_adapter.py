from __future__ import annotations

from pathlib import Path

from app.adapters.base import AdapterFailure
from app.config import Settings, get_settings


class GFPGANAdapter:
    def __init__(self, settings: Settings | None = None):
        self.settings = settings or get_settings()

    async def restore(
        self,
        input_path: str | Path,
        output_path: str | Path,
        operation: str = "face_restore",
    ) -> Path:
        raise AdapterFailure("GFPGAN or CodeFormer model is not configured yet")

