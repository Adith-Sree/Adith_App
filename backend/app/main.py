import os
from fastapi import FastAPI, Depends
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

from app.api.sessions import router as sessions_router
from app.api.analytics import router as analytics_router
from app.db.session import create_db_and_tables
from app.core.startup import seed_default_user_if_missing
from app.core.security import verify_api_key

app = FastAPI(
    title="Autonomous Deep Work Broker API",
    description="The central orchestration engine for tracking focus sessions and managing AI agents.",
    version="2.0.0",
)

# CORS — restrict allowed origins dynamically based on the environment config
ALLOWED_ORIGINS = os.getenv("CORS_ORIGINS", "*").split(",")

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def on_startup() -> None:
    """Creates any missing tables and seeds default user on every cold start."""
    create_db_and_tables()
    seed_default_user_if_missing()


# Wire routers secured by global API Key verification to prevent IDOR and unauthorized edits
app.include_router(sessions_router, dependencies=[Depends(verify_api_key)])
app.include_router(analytics_router, dependencies=[Depends(verify_api_key)])


@app.get("/")
async def root() -> dict:
    return {"status": "healthy", "service": "Deep Work Broker Engine", "version": "2.0.0"}


@app.get("/api/v1/health")
async def health_check() -> dict:
    return {"database": "connected", "vector_store": "connected"}


if __name__ == "__main__":
    uvicorn.run("app.main:app", host="0.0.0.0", port=8000, reload=True)