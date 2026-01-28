"""
Authentication Module - Advanced Security Features

Security Features:
1. Argon2id Password Hashing (strongest algorithm)
2. Refresh Token Rotation (short-lived access + long-lived refresh)
3. HMAC Request Signing (tamper-proof requests)
"""

import os
import hmac
import hashlib
from datetime import datetime, timedelta
from typing import Optional
from jose import JWTError, jwt
from argon2 import PasswordHasher
from argon2.exceptions import VerifyMismatchError
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════

SECRET_KEY = os.getenv("SECRET_KEY", "fallback-secret-key-change-in-production")
HMAC_SECRET = os.getenv("HMAC_SECRET", "fallback-secret-key-change-in-production") # Force explicit fallback here too
ALGORITHM = "HS256"

# Token Expiration Times
ACCESS_TOKEN_EXPIRE_MINUTES = 15  # Short-lived (15 minutes)
REFRESH_TOKEN_EXPIRE_DAYS = 7     # Long-lived (7 days)

# Argon2id Password Hasher (strongest algorithm)
ph = PasswordHasher(
    time_cost=2,      # Number of iterations
    memory_cost=65536, # 64MB memory
    parallelism=1,     # CPU threads
    hash_len=32,       # Output hash length
    salt_len=16        # Salt length
)

# ═══════════════════════════════════════════════════════════════════════════
# PASSWORD HASHING (Argon2id)
# ═══════════════════════════════════════════════════════════════════════════

def get_password_hash(password: str) -> str:
    """Hash password using Argon2id (strongest algorithm)"""
    return ph.hash(password)

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify password against Argon2id hash"""
    try:
        ph.verify(hashed_password, plain_password)
        return True
    except VerifyMismatchError:
        return False
    except Exception:
        return False

# ═══════════════════════════════════════════════════════════════════════════
# ACCESS TOKEN (Short-lived - 15 minutes)
# ═══════════════════════════════════════════════════════════════════════════

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    """
    Create short-lived access token (15 minutes default)
    Used for API authentication
    """
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    
    to_encode.update({
        "exp": expire,
        "type": "access",
        "iat": datetime.utcnow()
    })
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

def verify_access_token(token: str) -> Optional[dict]:
    """Verify and decode access token"""
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        if payload.get("type") != "access":
            return None
        return payload
    except JWTError:
        return None

# ═══════════════════════════════════════════════════════════════════════════
# REFRESH TOKEN (Long-lived - 7 days)
# ═══════════════════════════════════════════════════════════════════════════

def create_refresh_token(data: dict) -> str:
    """
    Create long-lived refresh token (7 days)
    Used to get new access tokens without re-login
    """
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)
    
    to_encode.update({
        "exp": expire,
        "type": "refresh",
        "iat": datetime.utcnow()
    })
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

def verify_refresh_token(token: str) -> Optional[dict]:
    """Verify and decode refresh token"""
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        if payload.get("type") != "refresh":
            return None
        return payload
    except JWTError:
        return None

# ═══════════════════════════════════════════════════════════════════════════
# HMAC REQUEST SIGNING (Tamper-proof requests)
# ═══════════════════════════════════════════════════════════════════════════

def generate_request_signature(data: str, timestamp: str) -> str:
    """
    Generate HMAC-SHA256 signature for request data
    
    Args:
        data: Request body as string
        timestamp: Unix timestamp as string
        
    Returns:
        Hex-encoded HMAC signature
    """
    message = f"{timestamp}:{data}"
    signature = hmac.new(
        HMAC_SECRET.encode(),
        message.encode(),
        hashlib.sha256
    ).hexdigest()
    return signature

def verify_request_signature(data: str, timestamp: str, signature: str, max_age_seconds: int = 300) -> bool:
    """
    Verify HMAC signature and check timestamp freshness
    
    Args:
        data: Request body as string
        timestamp: Unix timestamp as string
        signature: Provided HMAC signature
        max_age_seconds: Maximum age of request (default 5 minutes)
        
    Returns:
        True if signature is valid and timestamp is fresh
    """
    # Check timestamp freshness (prevent replay attacks)
    try:
        request_time = int(timestamp)
        # BUG FIX: datetime.utcnow().timestamp() treats naive UTC as local time!
        # Use time.time() which is always UTC epoch.
        import time
        current_time = int(time.time())
        if abs(current_time - request_time) > max_age_seconds:
            return False
    except (ValueError, TypeError):
        return False
    
    # Verify signature
    expected_signature = generate_request_signature(data, timestamp)
    return hmac.compare_digest(signature, expected_signature)

# ═══════════════════════════════════════════════════════════════════════════
# UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════

def decode_token(token: str) -> Optional[dict]:
    """Decode any token (access or refresh) without type checking"""
    try:
        return jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    except JWTError:
        return None
