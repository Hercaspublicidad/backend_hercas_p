from pathlib import Path
from typing import Literal

from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    APP_NAME: str = "Hercas Platform API"
    ENABLED_MODULES: list[Literal["cotizador"]] = Field(default_factory=lambda: ["cotizador"])
    APP_ENV: str = "development"
    CORS_ORIGINS: list[str] = Field(default_factory=lambda: ["*"])
    HTTP_TIMEOUT_SECONDS: float = Field(default=30, gt=0, le=120)
    MAX_REQUEST_BODY_BYTES: int = Field(default=1_048_576, ge=1_024, le=10_485_760)
    MAX_BEARER_TOKEN_LENGTH: int = Field(default=8_192, ge=512, le=16_384)
    ODOO_URL: str | None = None
    ODOO_DATABASE: str | None = None
    ODOO_API_KEY: SecretStr | None = None
    SUPABASE_URL: str | None = None
    SUPABASE_PUBLISHABLE_KEY: SecretStr | None = None
    SUPABASE_SECRET_KEY: SecretStr | None = None
    AUTH_SITE_URL: str = "http://localhost:3000"

    model_config = SettingsConfigDict(
        env_file=Path(__file__).resolve().parents[2] / ".env",
        env_file_encoding="utf-8", extra="ignore",
    )
