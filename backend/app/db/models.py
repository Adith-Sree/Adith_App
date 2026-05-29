from typing import Optional
from datetime import datetime
from sqlmodel import Field, SQLModel, Relationship

# Table 1: The User
# Normalization Rule: Keep user stats separate from their individual sessions.
class User(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    username: str = Field(index=True, unique=True)
    # CRITICAL: Default is 0 — no pre-stored score, earn it through real sessions.
    discipline_score: int = Field(default=0)

    # Relationship links (One User -> Many Sessions/Tasks)
    sessions: list["FocusSession"] = Relationship(back_populates="user")
    tasks: list["TaskGoal"] = Relationship(back_populates="user")


# Table 2: The Focus Session
# This represents the actual "contract" you sign when you start working.
class FocusSession(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    goal_description: str
    duration_minutes: int
    start_time: datetime = Field(default_factory=datetime.utcnow)
    # end_time is set when a session completes or is force-stopped.
    # Required for analytics time-grouping by day.
    # Indexed for faster query filtering in 7-day windows
    end_time: Optional[datetime] = Field(default=None, index=True)
    status: str = Field(default="active", index=True)  # Can be "active", "completed", or "failed"
    # score_delta records the exact points change from this session (+25 / -15 / etc.)
    # Stored denormalized here so analytics graph can accumulate without re-deriving.
    score_delta: int = Field(default=0)

    # The Foreign Key linking this session back to a specific user (Indexed)
    user_id: int = Field(foreign_key="user.id", index=True)

    # Relationship links
    user: Optional[User] = Relationship(back_populates="sessions")
    agent_logs: list["AgentLog"] = Relationship(back_populates="session")


# Table 3: The Agent Log
# Every time the AI agent interrupts or talks to you, we log it here.
class AgentLog(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    message: str
    timestamp: datetime = Field(default_factory=datetime.utcnow)

    # The Foreign Key linking this message to a specific focus session (Indexed)
    session_id: int = Field(foreign_key="focussession.id", index=True)
    session: Optional[FocusSession] = Relationship(back_populates="agent_logs")


# Table 4: The Task Goal Checklist
# Synchronized focus task checklist.
class TaskGoal(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    title: str = Field(index=True)
    done: bool = Field(default=False)

    # The Foreign Key linking this task back to a specific user
    user_id: int = Field(foreign_key="user.id", index=True)
    user: Optional[User] = Relationship(back_populates="tasks")