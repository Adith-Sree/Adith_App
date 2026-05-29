"""
backend/app/core/startup.py

Post-deployment initialization tasks.
Called from main.py on_startup AFTER the DB schema is created.

On a fresh Render deploy (empty DB), this seeds the default user
so the app is immediately usable without running reset_db.py manually.
"""
import os
from sqlmodel import Session, select
from app.db.models import User
from app.db.session import engine


def seed_default_user_if_missing() -> None:
    """
    Idempotent: only inserts the default user if they don't exist.
    Safe to call on every cold start.
    """
    with Session(engine) as session:
        existing = session.exec(
            select(User).where(User.username == "adith")
        ).first()
        if not existing:
            user = User(username="adith", discipline_score=500)
            session.add(user)
            session.commit()
            print("[STARTUP] Seeded default user: adith (score=500)")
        else:
            print(f"[STARTUP] Default user exists: id={existing.id}, score={existing.discipline_score}")
