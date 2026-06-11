"""
backend/app/core/security.py

Security middleware to validate request headers in production environments.
Supports standard static API keys and Google OAuth2 ID Token verification.
Protects endpoints from unauthorized manipulation or Insecure Direct Object References (IDOR).
"""
import os
from fastapi import HTTPException, Security, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from google.oauth2 import id_token
from google.auth.transport import requests

# Reads secrets from environment variables
API_KEY = os.getenv("APP_API_KEY", "")
GOOGLE_CLIENT_ID = os.getenv("GOOGLE_CLIENT_ID", "")

# Standard Bearer auth header helper
security_scheme = HTTPBearer(auto_error=False)

def verify_google_token(credentials: HTTPAuthorizationCredentials = Security(security_scheme)) -> dict:
    """
    Dependency injection validator for Google ID Tokens.
    Verifies the Google OAuth2 token sent in the Authorization header.
    Returns the decoded user info dict if valid.
    """
    if not GOOGLE_CLIENT_ID:
        # Development fallback: if Google Client ID is not configured, bypass Google Auth check
        return {"email": "dev-user@example.com", "name": "Dev User", "picture": ""}

    if not credentials or not credentials.credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Google Authorization Bearer token."
        )

    token = credentials.credentials
    try:
        # Verify the ID Token against Google's public certificates
        idinfo = id_token.verify_oauth2_token(token, requests.Request(), GOOGLE_CLIENT_ID)
        
        # Verify issuer is indeed Google
        if idinfo['iss'] not in ['accounts.google.com', 'https://accounts.google.com']:
            raise ValueError('Wrong issuer.')
            
        return idinfo
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"Invalid Google Authorization Token: {str(e)}"
        )


def verify_api_key(credentials: HTTPAuthorizationCredentials = Security(security_scheme)) -> bool:
    """
    Dependency injection validator. Handles both Google token authentication (if configured)
    and static API key authentication (for backward compatibility / automation scripts).
    """
    # 1. If Google Client ID is configured, prefer Google Token Verification
    if GOOGLE_CLIENT_ID:
        verify_google_token(credentials)
        return True

    # 2. Fallback to static API key verification
    if not API_KEY:
        # Backward-compatible: No security required if environment has no APP_API_KEY or GOOGLE_CLIENT_ID
        return True

    if not credentials or not credentials.credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing Authorization Bearer token."
        )

    token = credentials.credentials
    if token != API_KEY:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid Authorization token."
        )

    return True
