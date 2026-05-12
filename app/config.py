from functools import lru_cache

from dotenv import load_dotenv
from pydantic_settings import BaseSettings, SettingsConfigDict

# .env.local wins over .env when both exist (matches Next.js convention).
load_dotenv(".env")
load_dotenv(".env.local", override=True)


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=(".env", ".env.local"),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    DATABASE_URL: str
    JWT_SECRET: str
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRE_MINUTES: int = 60
    ALLOWED_ORIGINS: str = "*"
    PORT: int = 8000


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]
