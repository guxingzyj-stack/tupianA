from __future__ import annotations

from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

from app.config import get_settings


class AuthMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        path = request.url.path
        if path.startswith("/api/") and path != "/api/health":
            expected = get_settings().app_token
            received = request.headers.get("X-App-Token", "")
            if not expected or received != expected:
                return JSONResponse({"error": "应用 token 不对"}, status_code=401)
        return await call_next(request)

