from __future__ import annotations

import asyncio
import time
from collections import defaultdict, deque
from dataclasses import dataclass, field

from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

from app.config import get_settings


@dataclass
class _Bucket:
    timestamps: deque[float] = field(default_factory=deque)


class RateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app):
        super().__init__(app)
        self._buckets: dict[str, _Bucket] = defaultdict(_Bucket)
        self._lock = asyncio.Lock()

    async def dispatch(self, request: Request, call_next):
        path = request.url.path
        if path.startswith("/api/") and path != "/api/health":
            client_ip = request.client.host if request.client else "unknown"
            if not await self._allow(client_ip):
                return JSONResponse({"error": "操作太频繁,稍等一下"}, status_code=429)
        return await call_next(request)

    async def _allow(self, client_ip: str) -> bool:
        settings = get_settings()
        now = time.monotonic()
        window_start = now - 60
        async with self._lock:
            bucket = self._buckets[client_ip]
            while bucket.timestamps and bucket.timestamps[0] < window_start:
                bucket.timestamps.popleft()
            if len(bucket.timestamps) >= settings.rate_limit_per_minute:
                return False
            bucket.timestamps.append(now)
            self._cleanup(now)
            return True

    def _cleanup(self, now: float) -> None:
        window_start = now - 60
        empty_keys = [
            key
            for key, bucket in self._buckets.items()
            if not bucket.timestamps or bucket.timestamps[-1] < window_start
        ]
        for key in empty_keys:
            self._buckets.pop(key, None)

