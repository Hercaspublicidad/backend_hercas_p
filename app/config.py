from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):

    APP_NAME: str = "Sistema Externos API Odoo"
    APP_ENV: str = "development"

    ODOO_URL: str
    ODOO_DATABASE: str | None = None
    ODOO_API_KEY: str

    #SUPABASE_URL: str
    #SUPABASE_KEY: str

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore"
    )


settings = Settings()