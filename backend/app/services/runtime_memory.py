from __future__ import annotations

import ctypes
import gc
import platform
from functools import lru_cache


@lru_cache(maxsize=1)
def _libc():
    if platform.system().lower() != "linux":
        return None
    try:
        return ctypes.CDLL("libc.so.6")
    except OSError:
        return None


def release_memory() -> None:
    gc.collect()
    libc = _libc()
    if libc is not None:
        try:
            libc.malloc_trim(0)
        except Exception:
            pass
