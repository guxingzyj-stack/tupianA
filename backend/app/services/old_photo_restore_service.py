from __future__ import annotations

from pathlib import Path

from app.adapters.base import AdapterFailure
from app.adapters.gfpgan_adapter import GFPGANAdapter
from app.adapters.qwen_edit_adapter import QwenEditAdapter
from app.adapters.real_esrgan_adapter import RealESRGANAdapter
from app.engine.old_photo_restore import apply_local_old_photo_restore


async def restore_old_photo(
    input_path: str | Path,
    output_path: str | Path,
    *,
    intent: str,
    option_name: str,
) -> tuple[Path, str]:
    candidates = _adapter_candidates(input_path, output_path, intent, option_name)
    for adapter_name, call in candidates:
        try:
            return await call(), adapter_name
        except AdapterFailure:
            continue

    return (
        apply_local_old_photo_restore(
            input_path,
            output_path,
            intent=intent,
            option_name=option_name,
        ),
        "local_fallback",
    )


def _adapter_candidates(
    input_path: str | Path,
    output_path: str | Path,
    intent: str,
    option_name: str,
):
    qwen = QwenEditAdapter()
    gfpgan = GFPGANAdapter()
    esrgan = RealESRGANAdapter()
    candidates = []

    if "人脸专修" in intent or "脸更清楚" in option_name:
        candidates.append(
            (
                "gfpgan",
                lambda: gfpgan.restore(
                    input_path=input_path,
                    output_path=output_path,
                    operation="face_restore",
                ),
            )
        )
    if "去模糊" in intent or "超分" in intent:
        candidates.append(
            (
                "real_esrgan",
                lambda: esrgan.restore(
                    input_path=input_path,
                    output_path=output_path,
                    scale=2,
                ),
            )
        )
    candidates.append(
        (
            "qwen_edit",
            lambda: qwen.restore(
                input_path=input_path,
                output_path=output_path,
                instruction=intent,
            ),
        )
    )
    return candidates
