import asyncio
import contextlib
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from starlette.middleware.cors import CORSMiddleware

from app.api import analyze, device, enhance, health, template, video
from app.config import get_settings
from app.jobs.queue import get_registered_queue
from app.middleware.auth import AuthMiddleware
from app.middleware.rate_limit import RateLimitMiddleware
from app.services.storage_cleanup import cleanup_old_storage, start_storage_cleanup_loop
from app.storage.db import init_db


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    settings.file_base_dir.mkdir(parents=True, exist_ok=True)
    init_db(settings.db_path)
    await cleanup_old_storage(settings.storage_retention_hours)
    cleanup_task = start_storage_cleanup_loop(settings)
    queue = get_registered_queue()
    await queue.start(settings.worker_count)
    try:
        yield
    finally:
        cleanup_task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await cleanup_task
        await queue.stop()


def create_app() -> FastAPI:
    settings = get_settings()
    app = FastAPI(
        title="Photo Rescue Backend",
        version=settings.app_version,
        lifespan=lifespan,
    )

    settings.file_base_dir.mkdir(parents=True, exist_ok=True)
    app.mount("/files", StaticFiles(directory=str(settings.file_base_dir)), name="files")

    app.add_middleware(AuthMiddleware)
    app.add_middleware(RateLimitMiddleware)
    if settings.cors_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origins,
            allow_credentials=False,
            allow_methods=["*"],
            allow_headers=["*"],
        )

    app.include_router(health.router, prefix="/api")
    app.include_router(analyze.router, prefix="/api")
    app.include_router(enhance.router, prefix="/api")
    app.include_router(video.router, prefix="/api")
    app.include_router(template.router, prefix="/api")
    app.include_router(device.router, prefix="/api")

    @app.get("/")
    async def root_health_check() -> dict[str, str]:
        return {"status": "ok", "version": settings.app_version}

    return app


app = create_app()
