"""
app/db/session.py

The single source of truth for the database engine and the FastAPI
dependency injector. All endpoints import `get_session` from here.
"""
import os
from typing import Generator
from sqlmodel import Session, SQLModel, create_engine
from dotenv import load_dotenv

load_dotenv()

# Reads DATABASE_URL from .env
# Example: postgresql://user:password@localhost:5432/deepwork
DATABASE_URL = os.getenv("DATABASE_URL", "")

if not DATABASE_URL:
    raise RuntimeError(
        "DATABASE_URL is not set. Add it to backend/.env\n"
        "Example: DATABASE_URL=postgresql://user:pass@localhost:5432/deepwork"
    )

# Optimize database connection pooling for concurrent production environments
engine = create_engine(
    DATABASE_URL,
    echo=False,
    pool_size=20,          # Standard pool size (active connections per worker process)
    max_overflow=40,       # Allow burst of up to 40 additional connections under heavy load
    pool_timeout=30,       # Timeout of 30 seconds before failing if connections are exhausted
    pool_recycle=1800,     # Recycle connections older than 30 mins to prevent stale connection errors
)


def create_db_and_tables() -> None:
    """Creates all SQLModel tables and runs necessary schema migrations. Called on app startup."""
    SQLModel.metadata.create_all(engine)
    # Run manual column migration (create_all doesn't add columns to existing tables)
    from sqlmodel import text
    with Session(engine) as session:
        try:
            session.exec(text("ALTER TABLE taskgoal ADD COLUMN IF NOT EXISTS deadline DATE"))
            session.commit()
        except Exception as e:
            session.rollback()
            # SQLite does not support IF NOT EXISTS in ALTER TABLE in older versions, 
            # so we catch and ignore if it already exists or isn't supported.
            print(f"[Migration] Note: {e}")


def get_session() -> Generator[Session, None, None]:
    """
    FastAPI dependency injector.
    Opens a DB session per request and guarantees cleanup.
    Usage: db: Session = Depends(get_session)
    """
    with Session(engine) as session:
        yield session
