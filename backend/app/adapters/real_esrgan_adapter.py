from __future__ import annotations

from pathlib import Path

from app.adapters.base import AdapterFailure
from app.config import Settings, get_settings


class RealESRGANAdapter:
    def __init__(self, settings: Settings | None = None):
        self.settings = settings or get_settings()

    async def restore(
        self,
        input_path: str | Path,
        output_path: str | Path,
        scale: int = 2,
    ) -> Path:
        raise AdapterFailure("Real-ESRGAN model is not configured yet")

