from collections.abc import Generator

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import NullPool

from app.config import get_settings

settings = get_settings()

# Supavisor transaction-mode pooler does NOT support prepared statements.
# - NullPool: let Supavisor manage pooling, not SQLAlchemy.
# - prepare_threshold=None: psycopg3 disables its prepared-statement cache.
# Both are required; missing either produces "prepared statement does not exist" under load.
engine = create_engine(
    settings.DATABASE_URL,
    poolclass=NullPool,
    connect_args={"prepare_threshold": None},
)

SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
