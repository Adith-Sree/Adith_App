"""
app/api/goals.py

All task goals endpoints — fully wired to PostgreSQL via SQLModel.
Synchronizes checklist items in real-time.
"""
from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlmodel import Session, select

from app.db.models import TaskGoal, User
from app.db.session import get_session

router = APIRouter(prefix="/api/goals", tags=["Goals"])

# ──────────────────────────────────────────────
# Request/Response Schemas
# ──────────────────────────────────────────────

class CreateGoalRequest(BaseModel):
    title: str
    user_id: int = 1

class GoalResponse(BaseModel):
    id: int
    title: str
    done: bool
    user_id: int

class ToggleGoalRequest(BaseModel):
    done: bool

# ──────────────────────────────────────────────
# Endpoints
# ──────────────────────────────────────────────

@router.get("/users/{user_id}", response_model=List[GoalResponse])
def get_user_goals(
    user_id: int,
    db: Session = Depends(get_session),
) -> List[TaskGoal]:
    """Retrieves all task checklist goals for a specific user, ordered by ID."""
    statement = (
        select(TaskGoal)
        .where(TaskGoal.user_id == user_id)
        .order_by(TaskGoal.id)
    )
    return db.exec(statement).all()


@router.post("", response_model=GoalResponse, status_code=status.HTTP_201_CREATED)
def create_goal(
    payload: CreateGoalRequest,
    db: Session = Depends(get_session),
) -> TaskGoal:
    """Creates a new synchronized task goal in the database."""
    user = db.get(User, payload.user_id)
    if not user:
        raise HTTPException(
            status_code=404,
            detail=f"User with id={payload.user_id} not found."
        )

    goal = TaskGoal(
        title=payload.title,
        done=False,
        user_id=payload.user_id,
    )
    db.add(goal)
    db.commit()
    db.refresh(goal)
    return goal


@router.patch("/{goal_id}/toggle", response_model=GoalResponse)
def toggle_goal(
    goal_id: int,
    payload: ToggleGoalRequest,
    db: Session = Depends(get_session),
) -> TaskGoal:
    """Toggles the done/checkbox state of a specific goal."""
    goal = db.get(TaskGoal, goal_id)
    if not goal:
        raise HTTPException(
            status_code=404,
            detail=f"Goal with id={goal_id} not found."
        )

    goal.done = payload.done
    db.add(goal)
    db.commit()
    db.refresh(goal)
    return goal


@router.delete("/{goal_id}", status_code=status.HTTP_200_OK)
def delete_goal(
    goal_id: int,
    db: Session = Depends(get_session),
) -> dict:
    """Deletes a synchronized task goal from the database."""
    goal = db.get(TaskGoal, goal_id)
    if not goal:
        raise HTTPException(
            status_code=404,
            detail=f"Goal with id={goal_id} not found."
        )

    db.delete(goal)
    db.commit()
    return {"status": "deleted", "id": goal_id, "message": "Task goal deleted successfully."}
