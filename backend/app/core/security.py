"""
backend/app/core/security.py

Simple and robust security middleware to validate request headers in production environments.
Protects endpoints from unauthorized manipulation or Insecure Direct Object References (IDOR).
"""
import os
from fastapi import HTTPException, Security, status
from fastapi.security import APIKeyHeader

# Reads APP_API_KEY from environment variables. If unset, runs in open mode (useful for dev)
API_KEY = os.getenv("APP_API_KEY", "")
API_KEY_NAME = "Authorization"

# Checks incoming "Authorization" header
api_key_header = APIKeyHeader(name=API_KEY_NAME, auto_error=False)

def verify_api_key(api_key_header_val: str = Security(api_key_header)):
    """
    Dependency injection validator. If APP_API_KEY is configured in the environment,
    validates that the Authorization header matches the key (either as Bearer or plain).
    """
    if not API_KEY:
        # Backward-compatible: No security required if environment has no APP_API_KEY
        return True

    if not api_key_header_val:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Authorization API key header."
        )

    # Standardize Bearer prefix matching or direct matching
    expected_bearer = f"Bearer {API_KEY}"
    if api_key_header_val != expected_bearer and api_key_header_val != API_KEY:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid Authorization API key token."
        )

    return True
