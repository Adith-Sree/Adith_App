"""
app/api/analytics.py

GET /api/users/{user_id}/analytics

Returns the user's live discipline score and a 7-day graph of cumulative
score evolution, built exclusively from real database rows.

Scoring contract (mirrors agent.py tool):
  - Completed session (any duration committed):  +25 points
  - Force-stopped, < 10% complete:              -25 points
  - Force-stopped, 10–50% complete:             -15 points
  - Force-stopped, > 50% complete:               -5 points

Graph contract:
  - Always returns exactly 7 data points (Mon → today or today-6 → today).
  - If no sessions exist for a day, that day inherits the previous day's score.
  - If the database is completely empty, returns [0, 0, 0, 0, 0, 0, 0].
"""

from datetime import datetime, timedelta, timezone
from typing import Any
from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session, select

from app.db.models import FocusSession, User
from app.db.session import get_session

router = APIRouter(prefix="/api/users", tags=["Analytics"])


# ──────────────────────────────────────────────
# Pydantic-style response schemas (plain dicts for simplicity)
# ──────────────────────────────────────────────

def _session_to_dict(s: FocusSession) -> dict[str, Any]:
    """Converts a FocusSession ORM row to a JSON-safe dict for the response."""
    return {
        "id": s.id,
        "goal_description": s.goal_description,
        "duration_minutes": s.duration_minutes,
        "status": s.status,
        "score_delta": s.score_delta,
        "start_time": s.start_time.isoformat() if s.start_time else None,
        "end_time": s.end_time.isoformat() if s.end_time else None,
    }


def _calculate_penalty(duration_minutes: int, start_time: datetime, end_time: datetime) -> int:
    """
    Derives the penalty for a force-stopped session based on completion percentage.
    Mirrors the logic in agent.py's calculate_quitting_penalty tool.
    """
    minutes_worked = max(0, (end_time - start_time).total_seconds() / 60)
    if duration_minutes == 0:
        return -25  # Safety guard
    completion_pct = minutes_worked / duration_minutes
    if completion_pct < 0.10:
        return -25
    elif completion_pct < 0.50:
        return -15
    return -5


def _build_7day_graph(
    user_id: int,
    db: Session,
) -> list[int]:
    """
    Builds the 7-day cumulative discipline score graph.

    Strategy:
      1. Determine the window: [today - 6 days, today] in UTC.
      2. Fetch all finished sessions in that window, ordered by end_time.
      3. Bucket score_deltas by day index (0 = 6 days ago, 6 = today).
      4. Accumulate running sum across the 7 buckets.
      5. The baseline is fetched from the DB: current score minus all
         score_deltas in the window (so the graph starts where the user
         was 7 days ago, not at zero each time the window shifts).
    """
    today = datetime.now(timezone.utc).replace(hour=23, minute=59, second=59)
    window_start = (today - timedelta(days=6)).replace(hour=0, minute=0, second=0)

    # All finished sessions in the last 7 days
    statement = (
        select(FocusSession)
        .where(FocusSession.user_id == user_id)
        .where(FocusSession.status != "active")
        .where(FocusSession.end_time >= window_start)
        .where(FocusSession.end_time <= today)
        .order_by(FocusSession.end_time)  # type: ignore[arg-type]
    )
    sessions_in_window = db.exec(statement).all()

    # Compute baseline: user's score BEFORE the 7-day window
    user = db.get(User, user_id)
    current_score = user.discipline_score if user else 0
    window_deltas_sum = sum(s.score_delta for s in sessions_in_window)
    baseline_score = current_score - window_deltas_sum

    # Bucket deltas by day offset (0 = 6 days ago, 6 = today)
    daily_deltas: list[int] = [0] * 7
    for s in sessions_in_window:
        day_offset = (s.end_time.date() - window_start.date()).days  # type: ignore[union-attr]
        day_offset = max(0, min(6, day_offset))
        daily_deltas[day_offset] += s.score_delta

    # Accumulate into a running score line
    graph_points: list[int] = []
    running = baseline_score
    for delta in daily_deltas:
        running += delta
        graph_points.append(running)

    return graph_points


# ──────────────────────────────────────────────
# The Endpoint
# ──────────────────────────────────────────────

@router.get("/{user_id}/analytics")
def get_analytics(user_id: int, db: Session = Depends(get_session)) -> dict[str, Any]:
    """
    Returns the live discipline score and 7-day graph data for a user.

    Response shape:
    {
        "discipline_score": 75,
        "graph_points": [0, 0, 25, 25, 0, 50, 75],
        "session_history": [ { ...session row... }, ... ]
    }
    """
    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail=f"User with id={user_id} not found.")

    # Last 20 finished sessions for the history list (most recent first)
    history_stmt = (
        select(FocusSession)
        .where(FocusSession.user_id == user_id)
        .where(FocusSession.status != "active")
        .order_by(FocusSession.end_time.desc())  # type: ignore[union-attr]
        .limit(20)
    )
    history = db.exec(history_stmt).all()

    graph_points = _build_7day_graph(user_id, db)

    return {
        "discipline_score": user.discipline_score,
        "graph_points": graph_points,
        "session_history": [_session_to_dict(s) for s in history],
    }
