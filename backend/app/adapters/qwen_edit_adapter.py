from __future__ import annotations

from pathlib import Path

from app.adapters.base import AdapterFailure
from app.config import Settings, get_settings


class QwenEditAdapter:
    def __init__(self, settings: Settings | None = None):
        self.settings = settings or get_settings()

    async def restore(
        self,
        input_path: str | Path,
        output_path: str | Path,
        instruction: str,
    ) -> Path:
        raise AdapterFailure("Qwen image edit model is not configured yet")

