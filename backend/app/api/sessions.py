"""
app/api/sessions.py

All session lifecycle endpoints — now fully wired to PostgreSQL via SQLModel.
No more simulated/mock data. Every state change persists to the DB.

Endpoints:
  POST /api/sessions/start          — Create and persist a new FocusSession
  POST /api/sessions/{id}/abandon   — Trigger AI pushback stream (session stays active)
  POST /api/sessions/{id}/force-stop — Hard-terminate session, apply penalty, update score
  POST /api/sessions/{id}/complete   — Mark session as completed, reward +25 points
"""

import asyncio
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from sqlmodel import Session, select

from app.core.agent import generate_pushback_message
from app.db.models import FocusSession, User
from app.db.session import get_session

router = APIRouter(prefix="/api/sessions", tags=["Sessions"])


# ──────────────────────────────────────────────
# Request/Response Schemas
# ──────────────────────────────────────────────

class StartSessionRequest(BaseModel):
    """Payload the Flutter app sends when committing to a focus contract."""
    goal_description: str
    duration_minutes: int
    user_id: int = 1  # Defaults to the seeded user


class SessionResponse(BaseModel):
    id: int
    goal_description: str
    duration_minutes: int
    status: str
    score_delta: int
    user_id: int


# ──────────────────────────────────────────────
# Scoring Helper
# ──────────────────────────────────────────────

def _force_stop_penalty(duration_minutes: int, start_time: datetime, now: datetime) -> int:
    """
    Mirrors the logic in agent.py's calculate_quitting_penalty tool.
    Returns a NEGATIVE integer (the penalty).
    """
    minutes_worked = max(0.0, (now - start_time).total_seconds() / 60)
    if duration_minutes == 0:
        return -25
    pct = minutes_worked / duration_minutes
    if pct < 0.10:
        return -25
    elif pct < 0.50:
        return -15
    return -5


# ──────────────────────────────────────────────
# 1. Start a Session
# ──────────────────────────────────────────────

@router.post("/start", response_model=SessionResponse)
def start_session(
    payload: StartSessionRequest,
    db: Session = Depends(get_session),
) -> FocusSession:
    """
    Creates and persists a new FocusSession.
    Validates the user exists before committing the contract.
    """
    user = db.get(User, payload.user_id)
    if not user:
        raise HTTPException(
            status_code=404,
            detail=f"User with id={payload.user_id} not found. Run reset_db.py to seed the default user.",
        )

    session = FocusSession(
        goal_description=payload.goal_description,
        duration_minutes=payload.duration_minutes,
        start_time=datetime.now(timezone.utc).replace(tzinfo=None),  # Store as naive UTC
        status="active",
        score_delta=0,
        user_id=payload.user_id,
    )
    db.add(session)
    db.commit()
    db.refresh(session)

    return session


# ──────────────────────────────────────────────
# 2. Abandon Attempt — AI Pushback Stream
# ──────────────────────────────────────────────

@router.post("/{session_id}/abandon")
async def abandon_session(
    session_id: int,
    db: Session = Depends(get_session),
) -> StreamingResponse:
    """
    User clicked "GIVE UP". Reads the real session from the DB and
    streams the AI pushback message. The session remains ACTIVE —
    the user must hit force-stop to actually terminate it.
    """
    session = db.get(FocusSession, session_id)
    if not session:
        raise HTTPException(status_code=404, detail=f"Session {session_id} not found.")
    if session.status != "active":
        raise HTTPException(status_code=409, detail="Session is not active.")

    # Wake the AI agent with real session data, executed in a threadpool to prevent event loop blocking
    agent_response = await run_in_threadpool(
        generate_pushback_message,
        goal=session.goal_description,
        duration=session.duration_minutes,
    )

    async def token_streamer():
        words = agent_response.split(" ")
        for word in words:
            yield f"{word} ".encode("utf-8")
            await asyncio.sleep(0.05)

    # 409 Conflict signals Flutter to show the pushback stream (not end the session)
    return StreamingResponse(
        token_streamer(),
        status_code=409,
        media_type="text/plain",
    )


# ──────────────────────────────────────────────
# 3. Force Stop — Hard Termination with Penalty
# ──────────────────────────────────────────────

@router.post("/{session_id}/force-stop")
def force_stop_session(
    session_id: int,
    db: Session = Depends(get_session),
) -> dict:
    """
    Hard-terminates a session after the AI pushback.
    - Marks session as "failed"
    - Calculates penalty based on completion percentage
    - Applies penalty to User.discipline_score (floors at 0)
    - Returns the penalty so Flutter can display it
    """
    session = db.get(FocusSession, session_id)
    if not session:
        raise HTTPException(status_code=404, detail=f"Session {session_id} not found.")
    if session.status != "active":
        raise HTTPException(
            status_code=400,
            detail=f"Session {session_id} is already '{session.status}', not active.",
        )

    now = datetime.now(timezone.utc).replace(tzinfo=None)
    penalty = _force_stop_penalty(session.duration_minutes, session.start_time, now)

    # Update the session row
    session.status = "failed"
    session.end_time = now
    session.score_delta = penalty
    db.add(session)

    # Apply penalty to user (floor at 0 — negative score makes no sense)
    user = db.get(User, session.user_id)
    if user:
        user.discipline_score = max(0, user.discipline_score + penalty)
        db.add(user)

    db.commit()

    return {
        "status": "failed",
        "penalty": penalty,
        "new_score": user.discipline_score if user else 0,
        "message": f"Focus contract terminated. Discipline penalty: {penalty} pts.",
    }


# ──────────────────────────────────────────────
# 4. Complete — Timer Expired Successfully
# ──────────────────────────────────────────────

@router.post("/{session_id}/complete")
def complete_session(
    session_id: int,
    db: Session = Depends(get_session),
) -> dict:
    """
    Called by Flutter when the countdown timer reaches zero naturally.
    Awards +25 points unconditionally — the user earned the full contract.
    """
    COMPLETION_REWARD = 25

    session = db.get(FocusSession, session_id)
    if not session:
        raise HTTPException(status_code=404, detail=f"Session {session_id} not found.")
    if session.status != "active":
        raise HTTPException(
            status_code=400,
            detail=f"Session {session_id} is already '{session.status}', not active.",
        )

    now = datetime.now(timezone.utc).replace(tzinfo=None)

    session.status = "completed"
    session.end_time = now
    session.score_delta = COMPLETION_REWARD
    db.add(session)

    user = db.get(User, session.user_id)
    if user:
        user.discipline_score += COMPLETION_REWARD
        db.add(user)

    db.commit()

    return {
        "status": "completed",
        "reward": COMPLETION_REWARD,
        "new_score": user.discipline_score if user else COMPLETION_REWARD,
        "message": f"Focus contract fulfilled. Reward: +{COMPLETION_REWARD} pts.",
    }