from functools import lru_cache
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "photo-rescue-backend"
    app_version: str = "0.1.0"
    relay_base_url: str = ""
    relay_api_key: str = ""
    ai_model: str = "claude-sonnet-4-6"
    image_edit_model: str = "gpt-image-1.5-all"
    db_path: str = "./data/app.db"
    file_base: str = "./data/files"
    app_token: str = "dev-token-change-me"
    public_base_url: str = ""
    rate_limit_per_minute: int = Field(default=60, ge=1)
    worker_count: int = Field(default=1, ge=1)
    storage_retention_hours: int = Field(default=24, ge=1)
    storage_cleanup_interval_seconds: int = Field(default=3600, ge=60)
    cors_allow_origins: str = "http://localhost:8080,http://127.0.0.1:8080"

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    @property
    def db_file(self) -> Path:
        return Path(self.db_path)

    @property
    def file_base_dir(self) -> Path:
        return Path(self.file_base)

    @property
    def cors_origins(self) -> list[str]:
        return [origin.strip() for origin in self.cors_allow_origins.split(",") if origin.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
