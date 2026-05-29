"""
reset_db.py

Run this script ONCE to wipe and reinitialize the PostgreSQL database.
It drops all tables, recreates the schema from the current SQLModel models,
and seeds one default user (Adith, id=1) with discipline_score=0.

Usage:
    cd backend
    python reset_db.py
"""

import os
import sys

# Ensure the backend app package is importable
sys.path.insert(0, os.path.dirname(__file__))

from dotenv import load_dotenv
load_dotenv()

from sqlmodel import SQLModel, Session, create_engine, select
from app.db.models import User, FocusSession, AgentLog  # noqa: F401 — imported to register metadata

DATABASE_URL = os.getenv("DATABASE_URL", "")
if not DATABASE_URL:
    print("❌  ERROR: DATABASE_URL is not set in backend/.env")
    print("   Example: DATABASE_URL=postgresql://user:pass@localhost:5432/deepwork")
    sys.exit(1)

engine = create_engine(DATABASE_URL, echo=True)


def reset() -> None:
    print("\n🔴  Dropping all existing tables...")
    SQLModel.metadata.drop_all(engine)
    print("✅  All tables dropped.\n")

    print("🏗️   Recreating schema from current models...")
    SQLModel.metadata.create_all(engine)
    print("✅  Schema created.\n")

    print("🌱  Seeding default user...")
    with Session(engine) as session:
        # Check if user already exists (idempotent guard)
        existing = session.exec(select(User).where(User.username == "adith")).first()
        if existing:
            print(f"⚠️   User 'adith' already exists (id={existing.id}). Skipping seed.")
        else:
            default_user = User(
                username="adith",
                discipline_score=0,  # STRICT: starts at zero — no free points
            )
            session.add(default_user)
            session.commit()
            session.refresh(default_user)
            print(f"✅  Seeded user: id={default_user.id}, username='{default_user.username}', score={default_user.discipline_score}")

    print("\n🎯  Database reset complete. No mock data. Start earning your score.\n")


if __name__ == "__main__":
    reset()
