from fastapi import FastAPI, Depends, HTTPException, status, Header, Request, BackgroundTasks, WebSocket, WebSocketDisconnect
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy.orm import Session
from sqlalchemy import text, func, or_, and_
from datetime import timedelta, datetime
from typing import List # <--- Added this
import models, schemas, auth, database, fraud_engine, security, notifications, reporting
from logging_config import logger, log_transaction, log_login, log_security_event, log_error
import random
import json
import traceback
from sqlalchemy.orm import joinedload
import os
import google.generativeai as genai
from i18n import get_text

# AI Auto-Learning Scheduler
import daily_summary
try:
    import ai_scheduler
    AI_SCHEDULER_AVAILABLE = True
except ImportError:
    AI_SCHEDULER_AVAILABLE = False
    print("⚠️ ai_scheduler not available")

import dotenv
dotenv.load_dotenv(override=True)

# Trigger reload 2

# ═══════════════════════════════════════════════════════════════════════════
# RATE LIMITING - Brute Force Protection
# ═══════════════════════════════════════════════════════════════════════════
# ═══════════════════════════════════════════════════════════════════════════
# RATE LIMITING - Brute Force Protection
# ═══════════════════════════════════════════════════════════════════════════
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

# Helper to get real IP behind Cloudflare/Proxy
def get_real_ip(request: Request) -> str:
    # Cloudflare Tunnel passes the real user IP in this header
    cf_ip = request.headers.get("CF-Connecting-IP")
    if cf_ip:
        return cf_ip
    
    # Fallback to X-Forwarded-For
    forwarded = request.headers.get("X-Forwarded-For")
    if forwarded:
        return forwarded.split(",")[0]
        
    # Fallback to direct connection (e.g. localhost testing)
    return request.client.host if request.client else "127.0.0.1"

# Rate limiting enabled for brute force protection (FREE)
limiter = Limiter(key_func=get_real_ip) 

app = FastAPI(
    title="Safe Pay API",
    description="""
## Secure UPI Payment Application API

A production-grade payment application with:
- **3-Stage Fraud Detection** (Rules → Social Graph → AI)
- **Military-Grade Encryption** (AES-256 + Argon2id)
- **HMAC Request Signing** (Tamper-proof transactions)

### Key Features:
- 🔐 PIN-based authentication with device binding
- 🛡️ AI-powered fraud detection with 16 features
- ⚡ Sub-200ms response times
- 🔄 Token rotation for session security
    """,
    version="2.0.0",
    docs_url="/docs",
    redoc_url="/redoc"
)

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

@app.get("/health", tags=["System"], summary="Health Check")
def health_check():
    """Returns OK if the API server is running."""
    return {"status": "ok"}

# Add CORS middleware - SECURITY: Restrict to known origins
# In production, only allow your specific domains
ALLOWED_ORIGINS = [
    "http://localhost:8000",
    "http://localhost:3000",
    "http://127.0.0.1:8000",
    "https://*.trycloudflare.com",  # Cloudflare tunnel
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_origin_regex=r"https://.*\.trycloudflare\.com",  # Regex for dynamic tunnel URLs
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ═══════════════════════════════════════════════════════════════════════════
# WEBSOCKET MANAGER - Real-time Multi-Admin Sync (0.1s latency)
# ═══════════════════════════════════════════════════════════════════════════

class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)

    async def broadcast(self, message: dict):
        for connection in self.active_connections:
            try:
                await connection.send_json(message)
            except:
                pass # Already disconnected

manager = ConnectionManager()

@app.websocket("/ws/admin")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            # Just keep connection alive, we primarily push server -> client
            data = await websocket.receive_text()
    except WebSocketDisconnect:
        manager.disconnect(websocket)

app.mount("/static", StaticFiles(directory="static"), name="static")

# Create Database Tables
models.Base.metadata.create_all(bind=database.engine)

# Seed data removed - use import_mock_users.py for population

# ═══════════════════════════════════════════════════════════════════════════
# AI AUTO-LEARNING SCHEDULER STARTUP
# ═══════════════════════════════════════════════════════════════════════════

@app.on_event("startup")
async def startup_event():
    """Start the AI auto-learning scheduler on app startup"""
    if AI_SCHEDULER_AVAILABLE:
        try:
            ai_scheduler.start_scheduler(interval_hours=24)
            print("AI Auto-Learning Scheduler started (retrains every 24 hours)")
        except Exception as e:
            print(f"Failed to start AI scheduler: {e}")
            
    try:
        daily_summary.start_daily_summary_scheduler()
    except Exception as e:
        print(f"Failed to start Daily Summary scheduler: {e}")

    # Seed 5 Admin Accounts
    db = database.SessionLocal()
    try:
        admins = ["admin1", "admin2", "admin3", "admin4", "admin5"]
        for username in admins:
            existing = db.query(models.AdminUser).filter(models.AdminUser.username == username).first()
            if not existing:
                # Use a default secure password for specific admins
                # In production, these should be set via env vars or manual entry
                hashed_pw = auth.get_password_hash("zaferadmin@2026")
                new_admin = models.AdminUser(username=username, hashed_password=hashed_pw)
                db.add(new_admin)
                print(f"✅ Seeded Admin: {username}")
        db.commit()
    except Exception as e:
        print(f"❌ Failed to seed admins: {e}")
    finally:
        db.close()

@app.on_event("shutdown")
async def shutdown_event():
    """Stop the AI scheduler on app shutdown"""
    if AI_SCHEDULER_AVAILABLE:
        try:
            ai_scheduler.stop_scheduler()
            print("AI Scheduler stopped")
        except Exception:
            pass
            
    try:
        daily_summary.stop_daily_summary_scheduler()
    except Exception:
        pass

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

def get_db():
    db = database.SessionLocal()
    try:
        yield db
    finally:
        db.close()

def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = auth.jwt.decode(token, auth.SECRET_KEY, algorithms=[auth.ALGORITHM])
        username: str = payload.get("sub")
        if username is None:
            raise credentials_exception
    except auth.JWTError:
        raise credentials_exception
    user = db.query(models.User).filter(models.User.username == username).first()
    if user is None:
        raise credentials_exception
        
    # Check device_id match
    token_device_id = payload.get("device_id")
    # If the user has a device_id set in DB, the token must match it.
    # SECURE: Compare hashes
    # Device ID check removed as column doesn't exist in DB
    # if user.device_id_hash:
    #    token_device_hash = security.hash_value(token_device_id)
    #    if token_device_hash != user.device_id_hash:
    #        raise HTTPException(
    #            status_code=status.HTTP_401_UNAUTHORIZED,
    #            detail="Logged in on another device",
    #            headers={"WWW-Authenticate": "Bearer"},
    #        )
    
    # Update last_active_at conservatively (max once per minute) to reduce DB writes
    now = datetime.now()
    if not user.last_active_at or (now - user.last_active_at).total_seconds() > 60:
        user.last_active_at = now
        db.commit()
    
    # Refresh user to ensure latest state is returned
    # db.refresh(user) # Not strictly needed if we just committed, but good for consistency if fields changed
        
    return user

# ═══════════════════════════════════════════════════════════════════════════
# PHASE 2: INTEGRITY & TIME SYNC (The Seal)
# ═══════════════════════════════════════════════════════════════════════════

@app.get("/time")
async def get_server_time():
    """
    Time Sync Endpoint (Smart Time Drift)
    Returns current UTC timestamp so client can calculate offset.
    TRUST NO ONE: Client uses this to sync with server clock.
    """
    import time
    return {"timestamp": int(time.time())}

async def verify_integrity(
    request: Request, 
    x_signature: str = Header(None), 
    x_timestamp: str = Header(None)
):
    """
    HMAC Verification Dependency (The Seal)
    Ensures body + timestamp + secret matches signature.
    Prevents tampering and replay attacks.
    """
    # Allow missing headers for simple Get requests or if explicitly non-critical
    # BUT for Phase 2, we enforce it on transactions. 
    # If used as a dependency, it MUST fail if missing.
    if request.url.path in ["/docs", "/openapi.json", "/time"]:
        return

    if not x_signature or not x_timestamp:
        raise HTTPException(
            status_code=400, 
            detail="Missing Security Headers (X-Signature, X-Timestamp)"
        )
        
    try:
        # Read body without consuming it (FastAPI/Starlette caches it)
        body_bytes = await request.body()
        body_str = body_bytes.decode()
        
        # Verify
        is_valid = auth.verify_request_signature(body_str, x_timestamp, x_signature)
        
        if not is_valid:
             expected = auth.generate_request_signature(body_str, x_timestamp)
             print(f"🛑 INTEGRITY FAILURE DEBUG INFO:")
             print(f"   Received Sig: {x_signature}")
             print(f"   Expected Sig: {expected}")
             print(f"   Timestamp:    {x_timestamp}")
             print(f"   Body Len:     {len(body_str)}")
             print(f"   Body Content: {body_str}")
             
             raise HTTPException(
                status_code=403, 
                detail="Request Integrity Check Failed (HMAC Mismatch or Replay)"
            )
            
    except HTTPException:
        raise
    except Exception as e:
        print(f"⚠️ Integrity Check Error: {e}")
        raise HTTPException(status_code=403, detail="Integrity Check Failed")

@app.post("/token", response_model=schemas.Token)
@limiter.limit("5/minute")
def login_for_access_token(
    request: Request,
    form_data: OAuth2PasswordRequestForm = Depends(), 
    db: Session = Depends(get_db),
    x_device_id: str = Header(None),
    accept_language: str = Header("en", alias="Accept-Language"),
    force_logout: bool = False
):
    # Authenticate by Mobile Number OR Email (passed in form_data.username)
    # SECURE: Search by hash, not plain text
    identifier = form_data.username
    identifier_hash = security.hash_value(identifier)
    user = db.query(models.User).filter(
        (models.User.mobile_hash == identifier_hash) | 
        (models.User.email_hash == identifier_hash)
    ).first()
    
    # If not found, try username as fallback
    if not user:
         user = db.query(models.User).filter(models.User.username == identifier).first()

    # Verify mPIN from User table (fallback to BankAccount for migration)
    mpin = user.hashed_mpin if user else None
    bank_pin = user.bank_account.hashed_pin if (user and user.bank_account) else None
    
    is_valid_pin = False
    if mpin:
        if auth.verify_password(form_data.password, mpin):
            is_valid_pin = True
    elif bank_pin:
        if auth.verify_password(form_data.password, bank_pin):
            is_valid_pin = True

    if not user or not is_valid_pin:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect valid Mobile/Email or PIN",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    # Check Single Device Login
    if x_device_id:
        x_device_hash = security.hash_value(x_device_id)
        
        # Check against stored hash
        if user.device_id_hash and user.device_id_hash != x_device_hash:
            if not force_logout:
                # User is already logged in on another device
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail={
                        "message": get_text("already_logged_in", accept_language),
                        "info": "You are currently logged in on another device. To continue on this device, you must logout from the other device."
                    },
                )
            # Force logout from other device - update device_id automatically below
            print(f"Force logout approved for user {user.username}. Updating device to {x_device_id}")
        
        # Update device_id binding
        user.device_id_hash = x_device_hash
        user.device_id_encrypted = security.encrypt_value(x_device_id)  # AES-256 encrypted
        user.last_active_at = datetime.now()  # Mark as active now
        db.commit()

    # Record Login History (New Feature)
    try:
        if x_device_id:
            # Check if this device logged in very recently (e.g. last 5 seconds) to avoid dupes on retries
            # but generally we want to log every login session.
            
            client_ip = get_real_ip(request)
            device_hash = security.hash_value(x_device_id)
            
            # 0. DISCONNECT OTHER ACTIVE SESSIONS (Event-Based)
            # Find all other devices for this user that were "LOGIN" as their last event
            from sqlalchemy import select, desc
            
            # Get all unique device hashes for this user
            all_devices = db.query(models.LoginHistory.device_id_hash).filter(
                models.LoginHistory.user_id == user.id,
                models.LoginHistory.device_id_hash != device_hash
            ).distinct().all()
            
            for (other_device_hash,) in all_devices:
                # Get latest event for this device
                latest_event = db.query(models.LoginHistory).filter(
                    models.LoginHistory.user_id == user.id,
                    models.LoginHistory.device_id_hash == other_device_hash
                ).order_by(models.LoginHistory.timestamp.desc()).first()
                
                if latest_event and latest_event.event_type == "LOGIN":
                    print(f"Recording AUTO_DISCONNECT for remote device {other_device_hash}")
                    disconnect_record = models.LoginHistory(
                        user_id=user.id,
                        event_type="AUTO_DISCONNECT",
                        device_id_hash=other_device_hash,
                        device_id_encrypted=latest_event.device_id_encrypted,
                        ip_hash=security.hash_value(client_ip) if client_ip else None,
                        ip_encrypted=security.encrypt_value(client_ip) if client_ip else None
                    )
                    db.add(disconnect_record)

            # 1. Check for Active Session on CURRENT Device
            current_latest = db.query(models.LoginHistory).filter(
                models.LoginHistory.user_id == user.id,
                models.LoginHistory.device_id_hash == device_hash
            ).order_by(models.LoginHistory.timestamp.desc()).first()
            
            if current_latest and current_latest.event_type == "LOGIN":
                print(f"Device {x_device_id} already has an active session. Skipping duplicate LOGIN event.")
            else:
                # CREATE NEW LOGIN EVENT
                print(f"Recording NEW LOGIN event for user {user.username}")
                login_record = models.LoginHistory(
                    user_id=user.id,
                    event_type="LOGIN",
                    device_id_hash=device_hash,
                    device_id_encrypted=security.encrypt_value(x_device_id),
                    timestamp=datetime.now(),
                    ip_hash=security.hash_value(client_ip) if client_ip else None,
                    ip_encrypted=security.encrypt_value(client_ip) if client_ip else None
                )
                db.add(login_record)

                # 3. UPDATE DEVICE PROFILE
                device_profile = db.query(models.DeviceProfile).filter(
                    models.DeviceProfile.user_id == user.id,
                    models.DeviceProfile.device_id_hash == device_hash
                ).first()
                
                if device_profile:
                    device_profile.login_count += 1
                    device_profile.last_login_time = datetime.now()
                else:
                    count = db.query(models.DeviceProfile).filter(models.DeviceProfile.user_id == user.id).count()
                    new_name = f"Device {chr(65+count)}"
                    device_profile = models.DeviceProfile(
                        user_id=user.id,
                        device_id_hash=device_hash,
                        device_name=new_name,
                        login_count=1,
                        last_login_time=datetime.now()
                    )
                    db.add(device_profile)
                    user.total_device_count += 1
            
            db.commit()
    except Exception as e:
        print(f"Error saving login history: {e}")
        # Don't block login if history save fails
    
    access_token_expires = timedelta(minutes=auth.ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = auth.create_access_token(
        data={"sub": user.username, "device_id": x_device_id}, expires_delta=access_token_expires
    )
    
    # Create refresh token for token rotation (long-lived - 7 days)
    refresh_token = auth.create_refresh_token(
        data={"sub": user.username, "device_id": x_device_id}
    )
    
    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
        "expires_in": auth.ACCESS_TOKEN_EXPIRE_MINUTES * 60  # seconds
    }

# ═══════════════════════════════════════════════════════════════════════════
# REFRESH TOKEN ENDPOINT - Token Rotation (Issue new, revoke old)
# ═══════════════════════════════════════════════════════════════════════════
@app.post("/auth/refresh")
def refresh_token_endpoint(
    refresh_token: str = Header(..., alias="X-Refresh-Token"),
    db: Session = Depends(get_db)
):
    """
    Token Rotation: Exchange refresh token for new access + refresh tokens
    
    Security: The old refresh token is REVOKED after use.
    If someone tries to reuse a revoked token, it's flagged as suspicious.
    """
    payload = auth.verify_refresh_token(refresh_token)
    if not payload:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired refresh token"
        )
    
    username = payload.get("sub")
    device_id = payload.get("device_id")
    token_jti = payload.get("jti")  # Unique token ID
    
    # Check if token is revoked (Token Rotation Security)
    if token_jti:
        revoked = db.query(models.RevokedToken).filter(
            models.RevokedToken.token_jti == token_jti
        ).first()
        
        if revoked:
            # Someone is trying to reuse a revoked token!
            # This could be a token theft attempt
            print(f"🚨 SECURITY: Revoked refresh token reuse detected! User: {username}")
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token has been revoked (possible theft detected)"
            )
    
    # Verify user still exists
    user = db.query(models.User).filter(models.User.username == username).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
    # REVOKE the old token (Token Rotation)
    if token_jti:
        try:
            revoked_token = models.RevokedToken(
                token_jti=token_jti,
                user_id=user.id,
                expires_at=datetime.utcfromtimestamp(payload.get("exp", 0))
            )
            db.add(revoked_token)
            db.commit()
        except Exception as e:
            print(f"Warning: Could not revoke token: {e}")
            # Continue anyway - better to issue new token than block user
    
    # Create new access token
    new_access_token = auth.create_access_token(
        data={"sub": username, "device_id": device_id}
    )
    
    # Create NEW refresh token (Token Rotation)
    new_refresh_token = auth.create_refresh_token(
        data={"sub": username, "device_id": device_id}
    )
    
    return {
        "access_token": new_access_token,
        "refresh_token": new_refresh_token,  # NEW token issued
        "token_type": "bearer",
        "expires_in": auth.ACCESS_TOKEN_EXPIRE_MINUTES * 60
    }

@app.post("/auth/check-mobile", response_model=schemas.MobileCheckResponse)
def check_mobile(
    check: schemas.MobileCheckRequest,
    db: Session = Depends(get_db),
    x_device_id: str = Header(None)
):
    try:
        # Normalize input
        identifier = check.mobile_number.strip() # Raw input
        normalized = ''.join(filter(str.isdigit, identifier))
        
        # Calculate hashes for raw AND normalized (to support legacy + new)
        hashes = {security.hash_value(identifier), security.hash_value(normalized)}
        
        # Add +91 variation checks for robustness (login with/without code)
        if len(normalized) == 10:
             hashes.add(security.hash_value(f"+91{normalized}"))
             hashes.add(security.hash_value(f"91{normalized}"))
        
        # Search by hash
        user = db.query(models.User).filter(
            (models.User.mobile_hash.in_(hashes)) | 
            (models.User.email_hash == security.hash_value(identifier))
        ).first()
        
        if not user:
            # Check username just in case
            user = db.query(models.User).filter(models.User.username == identifier).first()
        
        if not user:
            return {
                "exists": False, 
                "status": "new",
                "upi_id": None,
                "has_device_conflict": False
            }
        
        # Check if PIN is set (Either mPIN or Bank PIN)
        # Child accounts only have mPIN, while normal accounts have both.
        # If either is present, the user is "existing".
        has_mpin = user.hashed_mpin is not None and user.hashed_mpin != "NULL"
        has_bank_pin = False
        if user.bank_account:
             has_bank_pin = user.bank_account.hashed_pin is not None and user.bank_account.hashed_pin != "NULL"
        
        if not has_mpin and not has_bank_pin:
            return {
                "exists": True, 
                "status": "new", 
                "upi_id": user.upi_id,
                "has_device_conflict": False
            }
        
        # Existing user with PIN - Check for device conflict
        has_device_conflict = False
        # Note: Conflict check removed from here to follow the "post-PIN" logic.
        # This prevents revealing device state to unauthorized users.
        
        return {
            "exists": True, 
            "status": "existing",
            "upi_id": user.upi_id,
            "has_device_conflict": has_device_conflict
        }
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(e))
@app.post("/auth/validate-signup")
def validate_signup_details(
    req: schemas.SignupValidatorRequest,
    db: Session = Depends(get_db)
):
    # Normalize mobile
    normalized = ''.join(filter(str.isdigit, req.mobile_number)) if req.mobile_number else None
    
    # Robust check matching register logic
    hashes = {security.hash_value(req.mobile_number), security.hash_value(normalized)}
    if normalized and len(normalized) == 10:
        hashes.add(security.hash_value(f"+91{normalized}"))
        hashes.add(security.hash_value(f"91{normalized}"))
    
    # Check for existing mobile
    db_mobile = db.query(models.User).filter(models.User.mobile_hash.in_(hashes)).first()
    if db_mobile:
        return {"valid": False, "detail": "Mobile already registered"}
    
    # Check for existing email
    if req.email:
        email_hash = security.hash_value(req.email)
        db_email = db.query(models.User).filter(models.User.email_hash == email_hash).first()
        if db_email:
            return {"valid": False, "detail": "Email already registered"}
            
    return {"valid": True}

@app.post("/auth/register", response_model=schemas.UserResponse)
def register_user(
    user: schemas.UserRegister,
    db: Session = Depends(get_db)
):
    # Normalize mobile
    normalized = ''.join(filter(str.isdigit, user.mobile_number)) if user.mobile_number else None
    
    # Check if user exists (check username OR mobile hash variations)
    # Robust check matching check_mobile logic
    hashes = {security.hash_value(user.mobile_number), security.hash_value(normalized)}
    if normalized and len(normalized) == 10:
        hashes.add(security.hash_value(f"+91{normalized}"))
        hashes.add(security.hash_value(f"91{normalized}"))
    
    db_user = db.query(models.User).filter(
        (models.User.username == user.username) | 
        (models.User.mobile_hash.in_(hashes))
    ).first()
    
    if db_user:
        raise HTTPException(status_code=400, detail="Username or Mobile already registered")
    
    # Generate default UPI ID if not provided
    # Fallback to username instead of specific suffix
    new_upi = user.username
    
    # Use normalized hash for primary storage
    primary_mobile_hash = security.hash_value(normalized) if normalized else security.hash_value(user.mobile_number)

    new_user = models.User(
        username=user.username,
        # Mobile: SECURE - Hash + Encrypt only (no plain text)
        mobile_hash=primary_mobile_hash,
        mobile_encrypted=security.encrypt_value(normalized) if normalized else None,
        # Email: SECURE - Hash + Encrypt only (no plain text)
        email_hash=security.hash_value(user.email) if user.email else None,
        email_encrypted=security.encrypt_value(user.email) if user.email else None,
        # UPI ID (shareable - kept plain)
        upi_id=new_upi,
        balance=1000.0, # Sign up bonus?
    )
    
    # Initialize profiles
    db.add(new_user)
    db.commit() # Commit to get ID
    db.refresh(new_user)
    
    # Create BankAccount (PIN not set yet)
    bank_account = models.BankAccount(
        user_id=new_user.id,
        bank_name=models.detect_bank(new_upi),
        upi_id=new_upi,
        hashed_pin=None  # No PIN set yet
    )
    db.add(bank_account)
    
    s_prof = models.SenderProfile(user_id=new_user.id)
    r_prof = models.ReceiverProfile(user_id=new_user.id)
    db.add(s_prof)
    db.add(r_prof)
    db.commit()
    
    return new_user

@app.post("/auth/signup")
@limiter.limit("5/minute")
def register_signup(
    request: Request,
    req: schemas.SignUpRequest,
    db: Session = Depends(get_db)
):
    # Normalize mobile
    normalized = ''.join(filter(str.isdigit, req.mobile_number)) if req.mobile_number else None
    
    # Robust check matching check_mobile logic
    hashes = {security.hash_value(req.mobile_number), security.hash_value(normalized)}
    if normalized and len(normalized) == 10:
        hashes.add(security.hash_value(f"+91{normalized}"))
        hashes.add(security.hash_value(f"91{normalized}"))
    
    # Check for existing mobile
    db_mobile = db.query(models.User).filter(models.User.mobile_hash.in_(hashes)).first()
    if db_mobile:
        raise HTTPException(status_code=400, detail="Mobile already registered")
    
    # Check for existing email (NEW)
    if req.email:
        email_hash = security.hash_value(req.email)
        db_email = db.query(models.User).filter(models.User.email_hash == email_hash).first()
        if db_email:
            raise HTTPException(status_code=400, detail="Email already registered")

    final_username = req.username
    db_user = db.query(models.User).filter(models.User.username == final_username).first()
    if db_user:
        suffix = normalized[-4:] if normalized else str(int(datetime.utcnow().timestamp()))[-4:]
        final_username = f"{req.username}_{suffix}"
    
    new_upi = f"{normalized}@zaferpay" if normalized else f"user_{int(datetime.utcnow().timestamp())}@zaferpay"

    
    # Use normalized hash for storage consistency
    primary_mobile_hash = security.hash_value(normalized) if normalized else security.hash_value(req.mobile_number)

    new_user = models.User(
        username=final_username,
        mobile_hash=primary_mobile_hash,
        mobile_encrypted=security.encrypt_value(normalized) if normalized else None,
        email_hash=security.hash_value(req.email) if req.email else None,
        email_encrypted=security.encrypt_value(req.email) if req.email else None,
        upi_id=new_upi,
        balance=0.0,
        encrypted_balance=security.encrypt_value("0.0"),
        hashed_mpin=auth.get_password_hash(req.pin),
        pin_updated_at=datetime.utcnow()
    )
    
    db.add(new_user)
    db.commit() 
    db.refresh(new_user)
    
    if req.has_bank_account:
        bank_account = models.BankAccount(
            user_id=new_user.id,
            bank_name=models.detect_bank(new_upi),
            upi_id=new_upi,
            hashed_pin=auth.get_password_hash(req.pin)
        )
        db.add(bank_account)
    
    s_prof = models.SenderProfile(user_id=new_user.id)
    r_prof = models.ReceiverProfile(user_id=new_user.id)
    db.add(s_prof)
    db.add(r_prof)
    db.commit()
    
    return {"msg": "User created successfully", "upi_id": new_upi}

@app.post("/auth/set-pin")
@limiter.limit("10/minute")
def set_pin(
    request: Request,
    req: schemas.PinSetRequest,
    db: Session = Depends(get_db)
):
    # Normalize input first
    normalized_mobile = ''.join(filter(str.isdigit, req.mobile_number))
    
    # SECURE: Search by hash (Check normalized AND raw for backward compat)
    hashes = {security.hash_value(req.mobile_number), security.hash_value(normalized_mobile)}
    
    user = db.query(models.User).filter(models.User.mobile_hash.in_(hashes)).first()
    
    if not user:
        # Check by username just in case
        user = db.query(models.User).filter(models.User.username == req.mobile_number).first()
        
    if not user:
        # NEW USER REGISTRATION via Set PIN
        # Always store NORMALIZED mobile for new users
        
        # Generate defaults
        username = f"User{normalized_mobile}"
        # Use provided UPI ID or fallback to mobile_number
        upi_id = req.upi_id if req.upi_id else normalized_mobile
        placeholder_email = f"{normalized_mobile}@example.com"
        
        new_user = models.User(
            username=username,
            # Mobile: SECURE - Hash + Encrypt only (no plain text)
            mobile_hash=security.hash_value(normalized_mobile),
            mobile_encrypted=security.encrypt_value(normalized_mobile),
            # Email: SECURE - Hash + Encrypt only (no plain text)
            email_hash=security.hash_value(placeholder_email),
            email_encrypted=security.encrypt_value(placeholder_email),
            # UPI ID (shareable - kept plain)
            upi_id=upi_id,
            # Balance: Dual storage (plain for speed, encrypted for security)
            balance=1000.0,  # Welcome Bonus (plain for fast queries)
            encrypted_balance=security.encrypt_value("1000.0"),  # Welcome Bonus (encrypted)
            hashed_mpin=auth.get_password_hash(req.pin),  # App Login mPIN
            pin_updated_at=datetime.utcnow()
        )
        db.add(new_user)
        db.commit()
        db.refresh(new_user)
        
        # Create BankAccount with PIN
        bank_account = models.BankAccount(
            user_id=new_user.id,
            bank_name=models.detect_bank(upi_id),
            upi_id=upi_id,
            hashed_pin=auth.get_password_hash(req.pin)
        )
        db.add(bank_account)
        
        # Initialize profiles
        s_prof = models.SenderProfile(user_id=new_user.id)
        r_prof = models.ReceiverProfile(user_id=new_user.id)
        db.add(s_prof)
        db.add(r_prof)
        db.commit()
        
        return {"msg": "User created and PIN set successfully"}
        
    # Existing user -> Update both mPIN and Bank PIN
    hashed_req_pin = auth.get_password_hash(req.pin)
    user.hashed_mpin = hashed_req_pin
    user.pin_updated_at = datetime.utcnow()
    if user.bank_account:
        user.bank_account.hashed_pin = hashed_req_pin
    
    db.commit()
    return {"msg": "PIN set successfully"}

@app.post("/logout")
def logout(
    request: Request,
    current_user: models.User = Depends(get_current_user), 
    db: Session = Depends(get_db),
    x_device_id: str = Header(None)
):
    """
    Logout: Record a permanent LOGOUT event (Immutable)
    """
    try:
        if x_device_id:
            client_ip = get_real_ip(request)
            device_hash = security.hash_value(x_device_id)
            
            # Check if there is an active session to log out
            latest_event = db.query(models.LoginHistory).filter(
                models.LoginHistory.user_id == current_user.id,
                models.LoginHistory.device_id_hash == device_hash
            ).order_by(models.LoginHistory.timestamp.desc()).first()
            
            if latest_event and latest_event.event_type == "LOGIN":
                print(f"Recording LOGOUT event for device {x_device_id}")
                logout_record = models.LoginHistory(
                    user_id=current_user.id,
                    event_type="LOGOUT",
                    device_id_hash=device_hash,
                    device_id_encrypted=security.encrypt_value(x_device_id),
                    ip_hash=security.hash_value(client_ip) if client_ip else None,
                    ip_encrypted=security.encrypt_value(client_ip) if client_ip else None
                )
                db.add(logout_record)
            else:
                print(f"Logout called but no active LOGIN session found for device {x_device_id}")

            # ALWAYS clear device binding if the logging out device is the currently bound one
            if current_user.device_id_hash == device_hash:
                print(f"Clearing device binding for user {current_user.username}")
                current_user.device_id_hash = None
                current_user.device_id_encrypted = None
        else:
            # No device ID provided - clear device binding unconditionally
            print(f"Logout without device ID - clearing all device binding for {current_user.username}")
            current_user.device_id_hash = None
            current_user.device_id_encrypted = None
    except Exception as e:
        print(f"Error recording logout event: {e}")
        # Still clear device binding on error to prevent lock-out
        try:
            current_user.device_id_hash = None
            current_user.device_id_encrypted = None
        except:
            pass

    current_user.last_active_at = None
    db.commit()
    print(f"User {current_user.username} logged out")
    return {
        "msg": "Successfully logged out",
        "username": current_user.username,
        "device_cleared": True
    }

@app.post("/users/me/fcm-token")
def update_fcm_token(
    fcm_token_update: schemas.FCMTokenUpdate,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Update the FCM Token for the current user to receive push notifications.
    """
    token = fcm_token_update.fcm_token
    logger.info(f"Updating FCM token for user {current_user.username} (id={current_user.id}) | token_prefix='{token[:20] if token else 'None'}...'")
    current_user.fcm_token = token
    db.commit()
    logger.info(f"FCM token saved successfully for user {current_user.username}")
    return {"msg": "FCM token updated successfully"}

@app.get("/users/me/bank", response_model=schemas.BankAccountResponse)
def get_my_bank(current_user: models.User = Depends(get_current_user)):
    """Returns the current user's bank account info (bank name & UPI ID)"""
    if not current_user.bank_account:
        raise HTTPException(status_code=404, detail="No bank account found")
    return current_user.bank_account

@app.post("/admin/migrate-bank-accounts")
def migrate_bank_accounts(db: Session = Depends(get_db)):
    """
    One-time migration: Creates BankAccount entries for existing users
    who don't have one yet. Copies hashed_password from the old column
    using raw SQL (since the column was removed from the ORM model).
    """
    # Step 1: Find users without bank accounts
    existing_bank_user_ids = db.query(models.BankAccount.user_id).all()
    existing_ids = {row[0] for row in existing_bank_user_ids}
    
    # Step 2: Try to read old hashed_password via raw SQL (column may still exist in DB)
    user_pins = {}
    try:
        raw_result = db.execute(text(
            "SELECT id, upi_id, hashed_password FROM users WHERE hashed_password IS NOT NULL"
        )).fetchall()
        for row in raw_result:
            user_pins[row[0]] = (row[1], row[2])  # user_id -> (upi_id, hashed_password)
    except Exception as e:
        print(f"⚠️ Could not read hashed_password column (may be dropped): {e}")
    
    # Step 3: Get all users
    all_users = db.query(models.User).all()
    
    created = 0
    for user in all_users:
        if user.id in existing_ids:
            continue  # Already has bank account
        
        # Copy old PIN if available
        old_pin = user_pins.get(user.id, (None, None))[1]
        
        bank_account = models.BankAccount(
            user_id=user.id,
            bank_name=models.detect_bank(user.upi_id),
            upi_id=user.upi_id or "",
            hashed_pin=old_pin  # Copy old PIN hash if it existed
        )
        db.add(bank_account)
        created += 1
    
    db.commit()
    return {
        "msg": f"Migration complete. Created {created} bank accounts.",
        "pins_copied": len([uid for uid in user_pins if uid not in existing_ids]),
        "total_users": len(all_users)
    }

@app.post("/admin/test-daily-summary")
def test_daily_summary(current_user: models.User = Depends(get_current_user)):
    """
    Test endpoint to manually trigger the daily summary notifications.
    It runs the same logic that the 10 PM scheduler runs.
    """
    if current_user.username != "admin": # Basic auth for test endpoint
         import logging
         logger = logging.getLogger("auth")
         logger.warning(f"User {current_user.username} tried to trigger daily summaries manually.")
         # Allow anyway for testing, or restrict
    
    try:
        # Run synchronously for the test
        daily_summary.send_daily_summaries()
        return {"msg": "Successfully triggered daily summary notifications."}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ═══════════════════════════════════════════════════════════════════════════
# BANK ENDPOINTS — Hierarchical (Bank Name → Details)
# ═══════════════════════════════════════════════════════════════════════════

@app.get("/banks", response_model=List[schemas.BankNameResponse])
def get_all_banks(db: Session = Depends(get_db)):
    """
    Level 1: Returns all bank names with account counts.
    Click a bank name to see its UPI IDs and PIN status.
    """
    result = db.query(
        models.BankAccount.bank_name,
        func.count(models.BankAccount.id).label("account_count")
    ).group_by(models.BankAccount.bank_name).order_by(models.BankAccount.bank_name).all()
    
    return [
        schemas.BankNameResponse(bank_name=row[0], account_count=row[1])
        for row in result
    ]


@app.get("/banks/{bank_name}", response_model=List[schemas.BankDetailResponse])
def get_bank_details(bank_name: str, db: Session = Depends(get_db)):
    """
    Level 2: Returns UPI IDs and PIN status for a specific bank.
    Only shown when user clicks on a bank name.
    """
    accounts = db.query(models.BankAccount).filter(
        models.BankAccount.bank_name == bank_name
    ).all()
    
    if not accounts:
        raise HTTPException(status_code=404, detail=f"No accounts found for bank: {bank_name}")
    
    details = []
    for acc in accounts:
        user = db.query(models.User).filter(models.User.id == acc.user_id).first()
        details.append(schemas.BankDetailResponse(
            upi_id=acc.upi_id,
            has_pin=bool(acc.hashed_pin),
            username=user.username if user else "Unknown"
        ))
    
    return details

@app.get("/users/me", response_model=schemas.UserResponse)
def read_users_me(current_user: models.User = Depends(get_current_user)):
    return current_user

@app.put("/users/profile", response_model=schemas.UserResponse)
def update_profile(
    profile_data: schemas.UserBase,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Update user profile information (fullname)"""
    if profile_data.full_name:
        current_user.full_name = profile_data.full_name
    
    db.commit()
    db.refresh(current_user)
    return current_user

@app.patch("/users/me/settings", response_model=schemas.UserResponse)
def update_user_settings(
    settings: schemas.SettingsUpdateRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Update user-specific app settings (e.g. biometrics) to persist across installs.
    """
    update_data = settings.dict(exclude_unset=True)
    
    if 'biometric_enabled' in update_data:
        current_user.biometric_enabled = update_data['biometric_enabled']
    if 'app_lock_enabled' in update_data:
        current_user.app_lock_enabled = update_data['app_lock_enabled']
    if 'summary_frequency' in update_data:
        current_user.summary_frequency = update_data['summary_frequency']
    if 'spending_limit_period' in update_data:
        current_user.spending_limit_period = update_data['spending_limit_period']
        
    if 'spending_limit' in update_data:
        current_user.spending_limit = update_data['spending_limit']
        if update_data['spending_limit'] is not None:
            current_user.spending_limit_updated_at = datetime.utcnow()
        else:
            current_user.spending_limit_updated_at = None
    
    db.commit()
    db.refresh(current_user)
    return current_user

@app.get("/users/me/devices", response_model=schemas.DeviceSummaryResponse)
def read_user_devices(current_user: models.User = Depends(get_current_user), db: Session = Depends(get_db)):
    """
    Returns the "One Truth" about user devices from the Optimized Table:
    - Total New Devices (Stored in User Table)
    - Login Count & Timings (Stored in Device Profiles)
    """
    # 1. Total (Instant from User Table)
    total_count = current_user.total_device_count
    
    # 2. Details (From Profile Table)
    profiles = db.query(models.DeviceProfile).filter(models.DeviceProfile.user_id == current_user.id).all()
    
    device_stats = []
    
    for p in profiles:
         # Optional: If you want Full History Timings, we join with history.
         # But user asked for "Count", which is now pre-calculated.
         # To give the "Timings" array, we still query history for that device.
         
         timings = db.query(models.LoginHistory.timestamp)\
             .filter(models.LoginHistory.user_id == current_user.id)\
             .filter(models.LoginHistory.device_id_hash == p.device_id_hash)\
             .order_by(models.LoginHistory.timestamp.asc()).all()
         
         # Convert list of tuples to list of datetimes
         timings_list = [t[0] for t in timings]

         device_stats.append(schemas.DeviceLoginStats(
            device_name=p.device_name,
            login_count=p.login_count, # READ FROM TABLE
            timings=timings_list
        ))
        
    return schemas.DeviceSummaryResponse(
        total_new_devices=len(profiles),
        devices=device_stats
    )

@app.get("/users/me/devices/{device_hash}/history", response_model=List[schemas.LoginHistoryResponse])
def read_device_history(device_hash: str, current_user: models.User = Depends(get_current_user), db: Session = Depends(get_db)):
    """
    Drill Down Level 3: Specific History for ONE Device
    """
    # Verify ownership
    profile = db.query(models.DeviceProfile).filter(
        models.DeviceProfile.user_id == current_user.id,
        models.DeviceProfile.device_id_hash == device_hash
    ).first()
    
    if not profile:
        raise HTTPException(status_code=404, detail="Device not found")
        
    history = db.query(models.LoginHistory).filter(
        models.LoginHistory.user_id == current_user.id,
        models.LoginHistory.device_id_hash == device_hash
    ).order_by(models.LoginHistory.timestamp.desc()).all()
    
    return history

@app.get("/users/lookup/{upi_id}", response_model=schemas.UserLookupResponse)
def lookup_user_by_upi(upi_id: str, current_user: models.User = Depends(get_current_user), db: Session = Depends(get_db)):
    # Case insensitive search using ILIKE (or equivalent in SQLite/PG)
    # Note: SQLite LIKE is case-insensitive for ASCII by default usually, but we implement robust check
    user = db.query(models.User).filter(models.User.upi_id == upi_id).first()
    
    if not user:
        # Try finding via case-insensitive matching if exact match failed
        # In SQLite, generic 'col LIKE val' is often case insensitive
        user = db.query(models.User).filter(models.User.upi_id.like(upi_id)).first()

    if not user:
        # AUTO-CREATE External User
        # This fixes issues where scanning a real QR code fails because the user isn't in our local DB
        # Check by UPI hash
        hashed_upi = security.hash_value(upi_id)
        
        # Generate username from UPI
        base_name = upi_id.split('@')[0] if '@' in upi_id else upi_id
        new_username = base_name
        
        # Ensure username uniqueness
        counter = 1
        while db.query(models.User).filter(models.User.username == new_username).first():
            new_username = f"{base_name}_{counter}"
            counter += 1
            
        # Create User
        user = models.User(
            username=new_username,
            upi_id=upi_id,
            balance=0.0,
        )
        db.add(user)
        try:
            db.commit()
            db.refresh(user)
            
            # Create BankAccount for external user
            ext_bank = models.BankAccount(
                user_id=user.id,
                bank_name=models.detect_bank(upi_id),
                upi_id=upi_id,
                hashed_pin=None
            )
            db.add(ext_bank)
            
            # Create Profiles
            s_prof = models.SenderProfile(user_id=user.id)
            r_prof = models.ReceiverProfile(user_id=user.id)
            db.add(s_prof)
            db.add(r_prof)
            db.commit()
        except Exception as e:
            db.rollback()
            print(f"Error auto-creating user: {e}")
            raise HTTPException(status_code=500, detail="Failed to register external user")
            
    return user

@app.get("/users/login-history", response_model=list[schemas.LoginHistoryResponse])
def get_login_history(current_user: models.User = Depends(get_current_user), db: Session = Depends(get_db)):
    history = db.query(models.LoginHistory).filter(
        models.LoginHistory.user_id == current_user.id
    ).order_by(models.LoginHistory.timestamp.desc()).all()
    return history

@app.get("/users/lookup-phone/{phone_number}", response_model=schemas.UserResponse)
def lookup_user_by_phone(phone_number: str, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    # Normalize phone number - remove all non-digit characters
    normalized_phone = ''.join(filter(str.isdigit, phone_number))
    
    # We need to check variations because we don't know exactly how it was stored
    # (some users might have +91, some might not, some might be new/normalized)
    
    variations = [
        normalized_phone,             # Raw digits (e.g. 9876543210)
        f"91{normalized_phone}",      # With 91 prefix
        f"+91{normalized_phone}",     # With +91 prefix
    ]
    
    # Also handle case where input ALREADY has 91 (e.g. input 9198765...)
    if len(normalized_phone) == 12 and normalized_phone.startswith("91"):
        no_prefix = normalized_phone[2:]
        if no_prefix not in variations:
            variations.append(no_prefix)
            variations.append(f"+91{no_prefix}") # +91 + digits

    # Calculate hashes for all variations
    hashes = [security.hash_value(v) for v in variations]
    
    # Query for any match
    user = db.query(models.User).filter(models.User.mobile_hash.in_(hashes)).first()

    if not user:
        raise HTTPException(status_code=404, detail="Phone number not found")
    return user

@app.get("/users/me/all-accounts", response_model=schemas.UserAccountsResponse)
def get_my_all_accounts(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Fetch all UPI IDs associated with the current user's mobile number"""
    # Simply use the mobile_hash of the current logged in user
    users = db.query(models.User).filter(models.User.mobile_hash == current_user.mobile_hash).all()
    return {"accounts": users}

@app.get("/users/search", response_model=List[schemas.PublicUserResponse])
def search_users(
    query: str,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    if len(query) < 3:
        return []
    
    # Case insensitive search on username
    # This returns public info only (username, upi_id, mcc)
    users = db.query(models.User).filter(
        models.User.username.ilike(f"%{query}%")
    ).limit(10).all()
    
    return users

@app.post("/users/lookup-contacts", response_model=schemas.ContactLookupResponse)
def lookup_contacts(
    req: schemas.ContactLookupRequest, 
    db: Session = Depends(get_db), 
    current_user: models.User = Depends(get_current_user)
):
    matches = []
    
    # 1. Pre-calculate all hashes for all numbers to do a single DB query
    # Map hash -> original phone number (to map back)
    hash_to_phone = {}
    
    for phone in req.phone_numbers:
        # Normalize
        normalized = ''.join(filter(str.isdigit, phone))
        variations = [normalized]
        if len(normalized) == 10:
            variations.append(f"91{normalized}")
            variations.append(f"+91{normalized}")
        elif len(normalized) == 12 and normalized.startswith("91"):
            variations.append(normalized[2:])
            variations.append(f"+91{normalized[2:]}")
            
        for v in variations:
            h = security.hash_value(v)
            # We map hash to the ORIGINAL input phone number so frontend knows which contact matched
            hash_to_phone[h] = phone 
            
    # 2. Bulk Query
    all_hashes = list(hash_to_phone.keys())
    found_users = db.query(models.User).filter(models.User.mobile_hash.in_(all_hashes)).all()
    
    # 3. Map results
    for user in found_users:
        # We need to find which original phone number this user corresponds to.
        # Since we have the user's mobile_hash, we can look it up in our map?
        # WAIT: The user table stores ONE mobile_hash (of the normalized version usually).
        # But we queried for variations.
        
        # We need to know WHICH hash matched. 
        # But SQL Alchemy doesn't tell us "this row matched because of this value in the IN clause" easily short of raw SQL.
        # BUT: The user.mobile_hash IS the value that matched.
        
        if user.mobile_hash in hash_to_phone:
            original_phone = hash_to_phone[user.mobile_hash]
            matches.append(schemas.ContactMatch(
                phone_number=original_phone,
                upi_id=user.upi_id,
                username=user.username
            ))
            
    return schemas.ContactLookupResponse(matches=matches)

@app.put("/users/me/change-mpin")
def change_mpin(
    req: schemas.ChangePinRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    # Verify current mPIN (fallback to bank account PIN if mPIN not set)
    current_hash = current_user.hashed_mpin or (current_user.bank_account.hashed_pin if current_user.bank_account else None)
    
    if not current_hash:
        raise HTTPException(status_code=400, detail="No PIN set. Use set-pin first.")
    
    if not auth.verify_password(req.current_pin, current_hash):
        raise HTTPException(status_code=401, detail="Incorrect current PIN")
    
    current_user.hashed_mpin = auth.get_password_hash(req.new_pin)
    db.commit()
    return {"msg": "App Login PIN updated successfully"}

@app.put("/users/me/disable-mpin")
def disable_mpin(
    req: schemas.VerifyPinRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Turns off App Lock by clearing the mPIN. Requires current mPIN."""
    current_hash = current_user.hashed_mpin
    
    if not current_hash:
        raise HTTPException(status_code=400, detail="mPIN is already disabled.")
    
    if not auth.verify_password(req.pin, current_hash):
        raise HTTPException(status_code=401, detail="Incorrect current mPIN")
    
    current_user.hashed_mpin = None
    db.commit()
    return {"msg": "App Lock has been disabled"}

@app.put("/users/me/enable-mpin")
def enable_mpin(
    req: schemas.VerifyPinRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Turns on App Lock by setting a new mPIN."""
    if current_user.hashed_mpin:
        raise HTTPException(status_code=400, detail="mPIN is already enabled.")
        
    current_user.hashed_mpin = auth.get_password_hash(req.pin)
    db.commit()
    return {"msg": "App Lock has been enabled"}

@app.put("/users/me/change-upi-pin")
def change_upi_pin(
    req: schemas.ChangePinRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    if not current_user.bank_account or not current_user.bank_account.hashed_pin:
        raise HTTPException(status_code=400, detail="No UPI PIN set. Use set-pin first.")
    
    if not auth.verify_password(req.current_pin, current_user.bank_account.hashed_pin):
        raise HTTPException(status_code=401, detail="Incorrect current UPI PIN")
    
    current_user.bank_account.hashed_pin = auth.get_password_hash(req.new_pin)
    current_user.pin_updated_at = datetime.utcnow()
    db.commit()
    return {"msg": "UPI PIN updated successfully"}

@app.post("/auth/verify-upi-pin")
@limiter.limit("5/minute")
def verify_upi_pin(
    request: Request,
    req: schemas.VerifyPinRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Fast pre-verification of UPI PIN before high-risk actions.
    """
    # Determine which hash to verify against
    # For Circle payments, use the App mPIN (as secondary users don't have bank accounts)
    target_hash = current_user.hashed_mpin if (req.is_circle_payment or not current_user.bank_account) else current_user.bank_account.hashed_pin
    
    if not target_hash:
        raise HTTPException(status_code=400, detail="No PIN set for this selection.")
        
    if not auth.verify_password(req.pin, target_hash):
        current_user.last_active_at = datetime.now()
        db.commit()
        raise HTTPException(status_code=401, detail="Incorrect UPI PIN")
        
    # Check 6-month expiration rule
    if current_user.pin_updated_at:
        age_days = (datetime.utcnow() - current_user.pin_updated_at).days
        if age_days >= 180:
            raise HTTPException(status_code=403, detail="PIN_EXPIRED")
        
    return {"msg": "UPI PIN verified successfully"}

# ═══════════════════════════════════════════════════════════════════════════
# PRE-PIN RISK ANALYSIS ENDPOINT
# ═══════════════════════════════════════════════════════════════════════════

@app.post("/transactions/analyze", response_model=schemas.TransactionAnalyzeResponse)
def analyze_transaction_risk(
    request: Request,
    tx: schemas.TransactionAnalyze,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    PRE-PIN FRAUD ANALYSIS
    
    Runs the full AI fraud engine BEFORE the user enters their PIN.
    This allows showing risk warnings upfront with a "Proceed Anyway" option.
    
    Returns:
    - risk_score: 'SAFE', 'WARN', or 'HIGH'
    - is_blocked: True if HIGH risk (user can still proceed if they acknowledge)
    - risk_reason: Fraud pattern code (F1, F2, etc.)
    """
    
    # CRITICAL DEBUG: Log that endpoint was called
    logger.info(f"🔍 ANALYZE ENDPOINT CALLED: {current_user.username} → {tx.receiver_upi_id} | ₹{tx.amount}")
    
    # 1. Validate Receiver exists
    lang = request.headers.get("accept-language", "en")
    receiver = db.query(models.User).filter(models.User.upi_id == tx.receiver_upi_id).first()
    receiver_name = receiver.username if receiver else "Unknown"
    receiver_exists = receiver is not None
    
    if not receiver:
        # Return safe analysis for unknown receivers (they'll be auto-created during transaction)
        return schemas.TransactionAnalyzeResponse(
            risk_score="WARN",
            risk_reason="NEW_RECEIVER",
            is_blocked=False,
            receiver_name="New Receiver",
            receiver_exists=False,
            detail={"message": get_text("first_time_receiver", lang), "risk": "WARN"}
        )

    # 1.5. Block if on call (v5.0 Scam Protection)
    if tx.is_on_call:
        return schemas.TransactionAnalyzeResponse(
            risk_score="FRAUD_BLOCKED",
            risk_reason="ON_CALL_RESTRICTION",
            is_blocked=True,
            receiver_name=receiver_name,
            receiver_exists=True,
            is_bypassable=False,
            detail={"message": get_text("fraud_blocked_call", lang), "risk": "FRAUD_BLOCKED"}
        )
        
    if receiver.is_fraud:
        return schemas.TransactionAnalyzeResponse(
            risk_score="FRAUD_BLOCKED",
            risk_reason="MANUAL_FLAG",
            is_blocked=True,
            receiver_name=receiver_name,
            receiver_exists=True,
            is_bypassable=False,
            detail={"message": get_text("fraud_blocked_flagged", lang), "risk": "FRAUD_BLOCKED"}
        )
    
    if receiver.id == current_user.id:
        return schemas.TransactionAnalyzeResponse(
            risk_score="HIGH",
            risk_reason="SELF_TRANSFER",
            is_blocked=True,
            receiver_name=receiver_name,
            receiver_exists=True,
            detail={"message": get_text("send_to_self", lang), "risk": "HIGH"}
        )

    # Restriction check in analysis phase
    is_receiver_child = receiver.bank_account is None
    if is_receiver_child:
        return schemas.TransactionAnalyzeResponse(
            risk_score="FRAUD_BLOCKED",
            risk_reason="CHILD_ACCOUNT_RESTRICTION",
            is_blocked=True,
            receiver_name=receiver_name,
            receiver_exists=True,
            is_bypassable=False,
            detail={"message": get_text("send_to_child", lang), "risk": "FRAUD_BLOCKED"}
        )
    
    # 2. Run Fraud Engine Analysis (without creating transaction)
    try:
        device_id = request.headers.get('X-Device-ID')
        device_hash = security.hash_value(device_id) if device_id else None
        client_ip = request.headers.get('X-Forwarded-For', request.client.host if request.client else None)
        if client_ip and ',' in client_ip:
            client_ip = client_ip.split(',')[0].strip()
        
        risk_label, risk_reason, fraud_features = fraud_engine.evaluate_fraud(
            db, current_user, receiver, tx.amount,
            device_id_hash=device_hash,
            receiver_mcc=tx.receiver_mcc,
            current_ip=client_ip,
            payment_source=tx.payment_source,
            is_screen_sharing=tx.is_screen_sharing
        )
        # Inject payment note for F61 keyword analysis (note is on the request, not on the user)
        if tx.note:
            fraud_features['payment_note'] = tx.note
    except Exception as e:
        # CRITICAL: Log the exact error
        logger.error(f"❌ FRAUD ENGINE ERROR: {e}")
        logger.error(f"   User: {current_user.username}")
        logger.error(f"   Receiver: {tx.receiver_upi_id}")
        logger.error(f"   Amount: ₹{tx.amount}")
        import traceback
        logger.error(f"   Traceback: {traceback.format_exc()}")
        
        # Return SAFE with error flag (don't block user due to system error)
        return schemas.TransactionAnalyzeResponse(
            risk_score="SAFE",
            risk_reason="ANALYSIS_ERROR",
            is_blocked=False,
            receiver_name=receiver_name,
            receiver_exists=True,
            is_bypassable=True,
            detail={
                "message": "Risk analysis temporarily unavailable. Transaction allowed.",
                "risk": "SAFE",
                "features": {"error": str(e)}
            }
        )
    
    # 3. Build response
    is_blocked = risk_label == "HIGH"
    
    detail_msg = {
        "SAFE": "Transaction appears safe",
        "WARN": "Unusual pattern detected - proceed with caution",
        "HIGH": "High risk transaction - review carefully before proceeding"
    }.get(risk_label, "Analysis complete")
    
    is_contact = fraud_features.get('is_contact', 0) == 1
    is_bypassable = risk_reason not in fraud_engine.HARD_BLOCK_REASONS
    
    return schemas.TransactionAnalyzeResponse(
        risk_score=risk_label,
        risk_reason=risk_reason,
        is_blocked=is_blocked,
        receiver_name=receiver_name,
        receiver_exists=True,
        is_contact=is_contact,
        is_bypassable=is_bypassable,
        detail={"message": detail_msg, "risk": risk_label, "features": fraud_features}
    )

@app.post("/transactions/", response_model=schemas.TransactionResponse, dependencies=[Depends(verify_integrity)])
def create_transaction(
    request: Request,
    tx: schemas.TransactionCreate, 
    background_tasks: BackgroundTasks,
    current_user: models.User = Depends(get_current_user), 
    db: Session = Depends(get_db)
):
    """
    DOUBLE-SPEND PROTECTED TRANSACTION
    
    This implementation uses SQLite-compatible locking to prevent race conditions:
    1. PIN verification (outside lock - fast fail)
    2. Receiver validation (outside lock - fast fail)
    3. ATOMIC BLOCK: Lock -> Re-read balance -> Transfer -> Commit/Rollback
    
    Idempotency Key: If provided, prevents duplicate transactions when user
    clicks pay button multiple times due to slow network.
    """

    # 0. Block if on call (v5.0 Scam Protection) - HARD BLOCK
    if tx.is_on_call:
        raise HTTPException(
            status_code=403, 
            detail="Transaction blocked for security. Please end your phone call to proceed."
        )
    
    # ═══════════════════════════════════════════════════════════════════════════
    # IDEMPOTENCY CHECK - Prevent Duplicate Transactions
    # ═══════════════════════════════════════════════════════════════════════════
    if tx.idempotency_key:
        # Check if this key was already processed
        existing_key = db.query(models.IdempotencyKey).filter(
            models.IdempotencyKey.key == tx.idempotency_key,
            models.IdempotencyKey.user_id == current_user.id
        ).first()
        
        if existing_key:
            # Key already processed - return cached response
            if existing_key.response_data:
                cached_response = json.loads(existing_key.response_data)
                return schemas.TransactionResponse(**cached_response)
            else:
                # Fallback: return basic response with original transaction
                if existing_key.transaction_id:
                    original_tx = db.query(models.Transaction).filter(
                        models.Transaction.transaction_id == existing_key.transaction_id
                    ).first()
                    if original_tx:
                        return schemas.TransactionResponse(
                            transaction_id=original_tx.transaction_id,
                            sender_upi_id=current_user.upi_id,
                            receiver_upi_id=original_tx.receiver.upi_id,
                            sender_name=current_user.username,
                            receiver_name=original_tx.receiver.username,
                            amount=original_tx.amount,
                            status=original_tx.status,
                            risk_score=original_tx.risk_score,
                            timestamp=original_tx.timestamp,
                            sender_bank_name=current_user.bank_name,
                            receiver_bank_name=original_tx.receiver.bank_name
                        )
                raise HTTPException(status_code=409, detail="Transaction already processed")
    
    # Identifiers for the logic below
    sender_id = current_user.id
    is_circle = tx.is_circle_payment and tx.circle_id is not None
    circle = None

    # Handle Payment Request Approval (Circle Flow)
    if tx.request_id:
        req = db.query(models.PaymentRequest).filter(models.PaymentRequest.id == tx.request_id).first()
        if req and req.circle_id and req.payer_id == current_user.id:
            # This is a circle approval! 
            # We override the transaction to be a circle payment initiated by the child
            is_circle = True
            tx.is_circle_payment = True
            tx.circle_id = req.circle_id
            
            # Verify recipient matches child's request
            if tx.receiver_upi_id != req.target_upi:
                raise HTTPException(status_code=400, detail="Recipient mismatch for circle approval.")

    if is_circle:
        # UPI CIRCLE LOGIC
        # Find circle where current user is either Secondary (Spender) or Primary (Approving an approval request)
        circle = db.query(models.UPICircle).filter(
            models.UPICircle.id == tx.circle_id
        ).first()
        
        if not circle or (circle.secondary_user_id != current_user.id and circle.primary_user_id != current_user.id):
            raise HTTPException(status_code=400, detail="Invalid or unauthorized UPI Circle")
        
        if circle.status != "ACTIVE":
            raise HTTPException(status_code=400, detail="UPI Circle is not active")

        # If Parent is paying for an approval request, we need to respect the child's limit
        if circle.current_monthly_spend + tx.amount > circle.monthly_limit:
            raise HTTPException(
                status_code=400, 
                detail=f"Circle monthly limit exceeded given by the parent account. Remaining: ₹{circle.monthly_limit - circle.current_monthly_spend}"
            )
            
        # Check Delegation Type
        if circle.delegation_type == "PARTIAL" and not tx.request_id:
            # STOP: Create a payment request for approval instead of moving money
            new_request = models.PaymentRequest(
                requester_id=current_user.id, # The Son
                payer_id=circle.primary_user_id, # The Father
                amount=tx.amount,
                status="pending",
                reason="Circle Approval Required",
                description=f"Payment to {tx.receiver_upi_id} via Circle",
                target_upi=tx.receiver_upi_id,
                circle_id=circle.id,
                timestamp=datetime.now()
            )
            db.add(new_request)
            db.commit()
            
            # Notify Primary User
            notifications.send_push_notification(
                db,
                circle.primary_user_id,
                "Circle Payment Approval",
                f"{current_user.username} wants to pay ₹{tx.amount} to {tx.receiver_upi_id}. Tap to approve.",
                "circle_approval"
            )
            db.commit()  # Commit the notification before raising
            
            raise HTTPException(
                status_code=202, # Accepted for processing (but not complete)
                detail={
                    "message": get_text("approval_sent", request.headers.get("accept-language", "en")),
                    "status": "PENDING_APPROVAL",
                    "request_id": new_request.id
                }
            )
        
        # If FULL delegation, the ACTUAL sender is the Primary User
        sender_id = circle.primary_user_id

    # Verify PIN (Argon2id)
    # NPCI Rule: Secondary users use App mPIN for Circle payments
    target_hash = current_user.hashed_mpin if (tx.is_circle_payment or not current_user.bank_account) else current_user.bank_account.hashed_pin
    
    if not target_hash:
        return {"status": "FAILED", "detail": "No PIN set"}

    if not auth.verify_password(tx.pin, target_hash):
        raise HTTPException(status_code=401, detail="Incorrect PIN")

    # Custom Spending Limit Check
    # NPCI Rule: Bypass spending limit ONLY for parent approving a child's circle request
    is_circle_approval = tx.request_id is not None and is_circle
    
    if not is_circle_approval and current_user.spending_limit and current_user.spending_limit_period:
        limit_period_days = current_user.spending_limit_period
        limit_amount = current_user.spending_limit
        
        start_time = datetime.now() - timedelta(days=limit_period_days)
        
        # We only count personal spending towards the personal limit.
        # Circle payments (where initiated_by_id is not None and not the current user) are EXCLUDED.
        spent_sum = db.query(func.sum(models.Transaction.amount)).filter(
            or_(
                and_(models.Transaction.sender_id == current_user.id, models.Transaction.initiated_by_id == None),
                models.Transaction.initiated_by_id == current_user.id
            ),
            models.Transaction.status == "SUCCESS",
            models.Transaction.timestamp >= start_time
        ).scalar() or 0.0
        
        if spent_sum + tx.amount > limit_amount:
            period_str = "Daily" if limit_period_days == 1 else f"{limit_period_days}-day"
            if limit_period_days == 7: period_str = "Weekly"
            if limit_period_days == 30: period_str = "Monthly"
            raise HTTPException(status_code=400, detail=f"{period_str} spending limit (₹{limit_amount}) reached.")

    # Re-calculate sender object if it's a circle payment
    effective_sender = current_user
    if is_circle:
        effective_sender = db.query(models.User).filter(models.User.id == sender_id).first()

    # 1. Validate Receiver (outside lock - fail fast)
    receiver = db.query(models.User).filter(models.User.upi_id == tx.receiver_upi_id).first()
    
    if receiver and receiver.is_fraud:
        raise HTTPException(
            status_code=403, 
            detail="Transaction blocked. This account has been flagged for fraudulent activity."
        )

    # Restriction: Cannot send money directly to a child account
    if receiver:
        is_receiver_child = receiver.bank_account is None
        if is_receiver_child:
            raise HTTPException(
                status_code=403,
                detail="Cannot send money directly to a child account. Please pay the parent instead."
            )

    if not receiver:
        # AUTO-REGISTER EXTERNAL USER
        # This allows payments to UPI IDs not yet in our system (Interop simulation)
        try:
             # Create dummy user for external UPI
             # Use timestamp to ensure uniqueness of "ext" mobile
             dummy_suffix = f"{int(datetime.now().timestamp())}{random.randint(1000,9999)}"
             dummy_mobile = f"ext{dummy_suffix}" 
             dummy_email = f"ext_{tx.receiver_upi_id}_{dummy_suffix}@external.mock"
             
             # Create hash/encrypted values
             mobile_hash = security.hash_value(dummy_mobile)
             mobile_enc = security.encrypt_value(dummy_mobile)
             email_hash = security.hash_value(dummy_email)
             email_enc = security.encrypt_value(dummy_email)
             
             new_receiver = models.User(
                 username=f"Ext User",
                 mobile_hash=mobile_hash,
                 mobile_encrypted=mobile_enc,
                 email_hash=email_hash,
                 email_encrypted=email_enc,
                 upi_id=tx.receiver_upi_id,
                 balance=0.0
             )
             db.add(new_receiver)
             db.commit()
             db.refresh(new_receiver)
             
             # Create BankAccount for external user
             ext_bank = models.BankAccount(
                 user_id=new_receiver.id,
                 bank_name=models.detect_bank(tx.receiver_upi_id),
                 upi_id=tx.receiver_upi_id,
                 hashed_pin=auth.get_password_hash("external_default")
             )
             db.add(ext_bank)
             
             # Init profiles
             db.add(models.SenderProfile(user_id=new_receiver.id))
             db.add(models.ReceiverProfile(user_id=new_receiver.id))
             db.commit()
             
             receiver = new_receiver
        except Exception as e:
             db.rollback()
             print(f"Failed to auto-register external user: {e}")
             # Look up one more time in case of race condition
             receiver = db.query(models.User).filter(models.User.upi_id == tx.receiver_upi_id).first()
             if not receiver:
                 raise HTTPException(status_code=404, detail="Receiver UPI ID not found and could not be registered")
    
    if receiver.id == current_user.id:
        raise HTTPException(status_code=400, detail="Cannot send money to self")

    # 2. Fraud Check (outside lock - informational)
    
    # Get client IP for geo-velocity check (F29) - ALWAYS extract for logging
    client_ip = request.headers.get('X-Forwarded-For', request.client.host if request.client else None)
    if client_ip and ',' in client_ip:
        client_ip = client_ip.split(',')[0].strip()  # First IP in chain is the client

    # Level 3 AI Check (F1-F54)
    device_id = request.headers.get('X-Device-ID')
    device_hash = security.hash_value(device_id) if device_id else None
    
    # SPEED OPTIMIZATION: Skip expensive fraud checks if already pre-checked by mobile app
    if tx.skip_fraud_check and tx.acknowledged_risk:
        risk_label = tx.acknowledged_risk
        risk_reason = "USER_ACKNOWLEDGED"
        fraud_features = {"pre_acknowledged": True}
        is_blocked = False
        status_str = "SUCCESS" if risk_label == "SAFE" else "FLAGGED"
        print(f"⚡ SPEED: Bypassing redundant fraud check (User Acknowledged)")
    else:
        # Full evaluation (fallback or first-time)
        risk_label, risk_reason, fraud_features = fraud_engine.evaluate_fraud(
            db, current_user, receiver, tx.amount,
            device_id_hash=device_hash,
            receiver_mcc=tx.receiver_mcc,
            current_ip=client_ip,
            payment_source=tx.payment_source,
            is_screen_sharing=tx.is_screen_sharing
        )
        # Inject payment note for F61 keyword analysis
        if tx.note:
            fraud_features['payment_note'] = tx.note
        
        is_blocked = False
        status_str = "SUCCESS"
        if risk_label == "HIGH":
            is_blocked = True
            status_str = "BLOCKED"
        elif risk_label == "WARN":
            status_str = "FLAGGED"

    # AI Logic: Decision Decision remains the same but uses consolidated variables above
    
    # Log to Brain Memory (FraudEvent) via Background Tasks for SPEED
    ai_score_value = fraud_features.get('ai_score', 0.0) if fraud_features else 0.0
    
    def background_fraud_logging(user_id: int, tx_id: str, amount: float, score: float, reason: str, blocked: bool):
        # Create a fresh session for background task
        bg_db = database.SessionLocal()
        try:
            fraud_engine.record_fraud_event(
                bg_db, 
                user_id=user_id,
                transaction_id=tx_id,
                amount=amount,
                ai_score=score,
                rule_violation=reason,
                is_blocked=blocked
            )
        finally:
            bg_db.close()
    
    if is_blocked:
        # ═══════════════════════════════════════════════════════════════════════
        # SAVE FAILED TRANSACTION TO DATABASE (So it appears in history)
        # ═══════════════════════════════════════════════════════════════════════
        failed_tx_id = f"TXN{int(datetime.now().timestamp()*1000)}"
        
        # Log to AI Brain Memory
        background_tasks.add_task(
            background_fraud_logging,
            user_id=effective_sender.id,
            tx_id=failed_tx_id,
            amount=tx.amount,
            score=ai_score_value,
            reason=risk_reason,
            blocked=True
        )
        
        failed_tx = models.Transaction(
            transaction_id=failed_tx_id,
            sender_id=effective_sender.id,
            receiver_id=receiver.id,
            initiated_by_id=current_user.id if is_circle else None,
            amount=tx.amount,
            status="FAILED",
            risk_score=risk_label,  # Should be String: 'SAFE', 'WARN', or 'HIGH'
            receiver_mcc=tx.receiver_mcc,
            timestamp=datetime.now(),
            # IP Tracking for audit
            ip_hash=security.hash_value(client_ip) if client_ip else None,
            ip_encrypted=security.encrypt_value(client_ip) if client_ip else None
        )
        db.add(failed_tx)
        db.commit()
        
        # ═══════════════════════════════════════════════════════════════════════
        # CUSTOM ERROR MESSAGES
        # ═══════════════════════════════════════════════════════════════════════
        
        # F18: Daily Per-Receiver Limit Exceeded
        if risk_reason == "F18_DAILY_RECEIVER_LIMIT_EXCEEDED":
            # Get tier to determine limit
            tier = fraud_engine.get_mcc_tier(tx.receiver_mcc)
            if tier == "PERSONAL":
                limit_str = "₹1,00,000"
            else:
                limit_str = "₹3,00,000"
            
            raise HTTPException(
                status_code=403,
                detail={
                    "message": get_text("limit_exceeded", request.headers.get("accept-language", "en"), limit=limit_str),
                    "reason": risk_reason,
                    "risk": risk_label,
                    "transaction_id": failed_tx_id,
                    "status": "FAILED"
                }
            )
        
        # Default blocked message
        raise HTTPException(
             status_code=403, 
             detail={
                 "message": get_text("transaction_blocked_security", request.headers.get("accept-language", "en")),
                 "reason": risk_reason,
                 "risk": risk_label,
                 "transaction_id": failed_tx_id,
                 "status": "FAILED"
             }
        )
    
    # 3. ATOMIC TRANSACTION BLOCK
    try:
        # Generate ID inside try block
        new_tx_id = f"TXN{int(datetime.now().timestamp()*1000)}"
        
        # Log to AI Brain Memory if suspicious or requested
        if risk_label != "SAFE" or fraud_features.get('should_log_fraud_event'):
            background_tasks.add_task(
                background_fraud_logging,
                user_id=effective_sender.id,
                tx_id=new_tx_id,
                amount=tx.amount,
                score=ai_score_value,
                reason=risk_reason or "SUSPICIOUS_PATTERN",
                blocked=False
            )
        
        # PESSIMISTIC LOCKING (Postgres Compatible)
        # We must lock both users to prevent race conditions.
        # DEADLOCK PREVENTION: Always lock users in ID order (smaller ID first)
        
        first_id, second_id = sorted([effective_sender.id, receiver.id])
        
        # Lock first user
        u1 = db.query(models.User).with_for_update().filter(models.User.id == first_id).first()
        # Lock second user
        u2 = db.query(models.User).with_for_update().filter(models.User.id == second_id).first()
        
        if not u1 or not u2:
             raise HTTPException(status_code=404, detail="User not found during transaction lock")
             
        # Identify which is sender/receiver after locking
        sender_user = u1 if u1.id == effective_sender.id else u2
        receiver_user = u1 if u1.id == receiver.id else u2
        
        # Re-check balance (Critical!)
        if sender_user.balance < tx.amount:
             raise HTTPException(status_code=400, detail="Insufficient balance")
             
        # Execute Transfer (Using encrypted balance method)
        sender_user.update_balance(sender_user.balance - tx.amount)
        receiver_user.update_balance(receiver_user.balance + tx.amount)

        # B2. UPDATE MERCHANT CATEGORY (if provided and valid)
        if tx.receiver_mcc and tx.receiver_mcc != '0000':
            # We trust the transaction source (QR code) more than default '0000'
            receiver_user.mcc = tx.receiver_mcc
        
        # C. CREATE TRANSACTION RECORD
        transaction_id = f"TXN{int(datetime.now().timestamp()*1000)}"
        new_tx = models.Transaction(
            transaction_id=transaction_id,
            sender_id=sender_user.id,
            receiver_id=receiver_user.id,
            initiated_by_id=circle.secondary_user_id if is_circle else None,
            amount=tx.amount,
            encrypted_amount=security.encrypt_value(tx.amount),
            status="SUCCESS",
            risk_score=risk_label,
            timestamp=datetime.now(),
            note=tx.note,  # Save Note
            # IP Tracking for Geo-Velocity (F29)
            ip_hash=security.hash_value(client_ip) if client_ip else None,
            ip_encrypted=security.encrypt_value(client_ip) if client_ip else None,
            receiver_mcc=tx.receiver_mcc
        )
        db.add(new_tx)

        # D. UPDATE PROFILES (Best Effort / Part of Transaction)
        # SELF-HEALING: Auto-create profile if missing
        if not sender_user.sender_profile:
            print(f"Healing missing sender profile for user {sender_user.id}")
            sender_user.sender_profile = models.SenderProfile(user_id=sender_user.id)
            db.add(sender_user.sender_profile)

        if sender_user.sender_profile:
            # Initialize to 0 if None (newly created or corrupted data)
            if sender_user.sender_profile.total_transactions_count is None:
                sender_user.sender_profile.total_transactions_count = 0
            if sender_user.sender_profile.total_transactions_amount is None:
                sender_user.sender_profile.total_transactions_amount = 0.0
            
            sender_user.sender_profile.total_transactions_count += 1
            sender_user.sender_profile.total_transactions_amount += tx.amount
            sender_user.sender_profile.last_transaction_time = datetime.now()
            if sender_user.sender_profile.total_transactions_count > 0:
                sender_user.sender_profile.avg_transaction_amount = (
                    sender_user.sender_profile.total_transactions_amount / 
                    sender_user.sender_profile.total_transactions_count
                )
        
        # SELF-HEALING: Auto-create receiver profile if missing
        if not receiver_user.receiver_profile:
            print(f"Healing missing receiver profile for user {receiver_user.id}")
            receiver_user.receiver_profile = models.ReceiverProfile(user_id=receiver_user.id)
            db.add(receiver_user.receiver_profile)

        if receiver_user.receiver_profile:
            # Initialize to 0 if None (newly created or corrupted data)
            if receiver_user.receiver_profile.total_received_count is None:
                receiver_user.receiver_profile.total_received_count = 0
            if receiver_user.receiver_profile.total_received_amount is None:
                receiver_user.receiver_profile.total_received_amount = 0.0
            
            receiver_user.receiver_profile.total_received_count += 1
            receiver_user.receiver_profile.total_received_amount += tx.amount
            receiver_user.receiver_profile.last_received_time = datetime.now()

        # F. UPDATE CIRCLE LIMITS
        if is_circle and circle:
            circle.current_monthly_spend += tx.amount
            circle.last_spent_at = datetime.now()

        # E. IDEMPOTENCY KEY
        if tx.idempotency_key:
            response_obj = {
                "transaction_id": transaction_id,
                "sender_upi_id": sender_user.upi_id,
                "receiver_upi_id": receiver_user.upi_id,
                "sender_name": sender_user.username,
                "receiver_name": receiver_user.username,
                "amount": tx.amount,
                "status": "SUCCESS",
                "risk_score": risk_label,
                "timestamp": new_tx.timestamp.isoformat(),
                "sender_bank_name": sender_user.bank_name,
                "receiver_bank_name": receiver_user.bank_name,
                "initiated_by_name": current_user.username if is_circle else None,
                "initiated_by_upi": current_user.upi_id if is_circle else None
            }
            new_idemp = models.IdempotencyKey(
                key=tx.idempotency_key,
                user_id=sender_user.id,
                transaction_id=transaction_id,
                response_status="200",
                response_data=json.dumps(response_obj)
            )
            db.add(new_idemp)

        # COMMIT EVERYTHING
        db.commit()
        db.refresh(new_tx)
        
        # F. PUSH NOTIFICATION (Fire & Forget via Background Tasks)
        try:
            if receiver_user.fcm_token:
                background_tasks.add_task(
                    notifications.send_fcm_notification,
                    token=receiver_user.fcm_token,
                    title=f"Money Received from {sender_user.username}!",
                    body=f"You received ₹{tx.amount}",
                    data={
                        "type": "transaction_received",
                        "transaction_id": transaction_id,
                        "amount": str(tx.amount),
                        "sender_name": sender_user.username
                    }
                )
        except Exception as e:
            print(f"Failed to queue push notification: {e}")
        
        # ═══════════════════════════════════════════════════════════════════════
        # BACKGROUND TASKS (Speed Optimization)
        # ═══════════════════════════════════════════════════════════════════════
        # Move all non-critical DB updates to background tasks so user gets 
        # success response IMMEDIATELY.
        
        def run_background_tx_tasks(s_id: int, r_id: int, r_upi: str, amt: float, acknowledged: bool, risk: str, request_id: int = None):
            # We get a fresh DB session for background work to avoid thread issues
            from database import SessionLocal
            bg_db = SessionLocal()
            try:
                # Update Trust Graph
                fraud_engine.record_trust(bg_db, s_id, r_id)
                
                # Adaptive Learning
                s_user = bg_db.query(models.User).filter(models.User.id == s_id).first()
                if s_user:
                    fraud_engine.update_adaptive_memory(bg_db, s_user, amt, acknowledged)
                
                # Bank Reporting
                if risk in ["WARN", "HIGH"]:
                    d_ago = datetime.now() - timedelta(hours=24)
                    risky_count = bg_db.query(models.Transaction).filter(
                        models.Transaction.sender_id == s_id,
                        models.Transaction.status == "SUCCESS",
                        models.Transaction.risk_score.in_(["WARN", "HIGH"]),
                        models.Transaction.timestamp >= d_ago
                    ).count()
                    
                    if risky_count >= 5:
                        reporting.send_automated_bank_report(s_id)
                
                # Handle Payment Request Status (Moved to background for speed)
                if request_id:
                    pr = bg_db.query(models.PaymentRequest).filter(models.PaymentRequest.id == request_id).first()
                    if pr:
                        # Verify parties one last time in background
                        if pr.payer_id == s_id and (pr.target_upi == r_upi or pr.requester_id == r_id):
                            pr.status = "paid"
                            pr.updated_at = datetime.now()
                            bg_db.commit()
                            print(f"✅ Background: Marked PaymentRequest {request_id} as PAID")

            except Exception as bg_e:
                print(f"⚠️ Background Task Failed: {bg_e}")
            finally:
                bg_db.close()

        background_tasks.add_task(
            run_background_tx_tasks,
            sender_user.id,
            receiver_user.id,
            receiver_user.upi_id,
            tx.amount,
            tx.acknowledged_risk is not None,
            risk_label,
            tx.request_id
        )
        



    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        import os
        import sys
        
        # Absolute path to ensure we find the file
        log_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "error_traceback.log")
        
        # Print to stderr for immediate visibility
        print(f"!!! CRITICAL TRANSACTION ERROR: {e}", file=sys.stderr)
        traceback.print_exc()
        
        try:
            with open(log_path, "w") as f:
                f.write(f"Error: {str(e)}\n")
                traceback.print_exc(file=f)
            print(f"Traceback written to {log_path}", file=sys.stderr)
        except Exception as write_err:
             print(f"Failed to write log file: {write_err}", file=sys.stderr)

        raise HTTPException(status_code=500, detail=f"Transaction failed due to system error: {str(e)}")
        

    # Invalidate Cache for all parties to ensure immediate UI update
    clear_home_cache(sender_user.id)
    if receiver_user:
        clear_home_cache(receiver_user.id)
    if current_user.id != sender_user.id:
        clear_home_cache(current_user.id)
    # Also invalidate child's cache and notify for circle payments
    if is_circle and circle:
        child_user_id = circle.secondary_user_id
        clear_home_cache(child_user_id)
        # Notify the child that their circle payment was approved and completed
        try:
            notifications.send_push_notification(
                db,
                child_user_id,
                "Payment Approved",
                f"Your payment of ₹{tx.amount} to {receiver_user.username} was approved and completed.",
                "circle_payment_approved",
                background_tasks=background_tasks
            )
            db.commit()
        except Exception as e:
            print(f"Failed to send circle approval notification to child: {e}")

    return schemas.TransactionResponse(
        transaction_id=new_tx.transaction_id,
        sender_upi_id=sender_user.upi_id,
        receiver_upi_id=receiver_user.upi_id,
        sender_name=sender_user.username,
        receiver_name=receiver_user.username,
        sender_full_name=sender_user.full_name,
        receiver_full_name=receiver_user.full_name,
        amount=new_tx.amount,
        status="SUCCESS",
        risk_score=risk_label,
        timestamp=new_tx.timestamp,
        note=new_tx.note,
        sender_bank_name=sender_user.bank_name,
        receiver_bank_name=receiver_user.bank_name,
        initiated_by_name=circle.secondary_user.username if is_circle else None,
        initiated_by_upi=circle.secondary_user.upi_id if is_circle else None
    )


# Simple In-Memory Cache for Home Data
# Key: user_id, Value: (timestamp, data)
HOME_DATA_CACHE = {}
CACHE_TTL = 5 # seconds

def clear_home_cache(user_id: int):
    """Force home data to re-fetch on next request by invalidating cache"""
    if user_id in HOME_DATA_CACHE:
        del HOME_DATA_CACHE[user_id]

@app.get("/home-aggregate", response_model=schemas.HomeAggregateResponse)
def get_home_aggregate(
    current_user: models.User = Depends(get_current_user), 
    db: Session = Depends(get_db)
):
    # Check Cache
    if current_user.id in HOME_DATA_CACHE:
        ts, cached_data = HOME_DATA_CACHE[current_user.id]
        if (datetime.now() - ts).total_seconds() < CACHE_TTL:
            return cached_data

    from sqlalchemy.orm import joinedload
    
    # 1. Get History (Limit 10) - Eager Load
    history_txs = db.query(models.Transaction).options(
        joinedload(models.Transaction.sender), 
        joinedload(models.Transaction.receiver),
        joinedload(models.Transaction.initiated_by)
    ).filter(
        (models.Transaction.sender_id == current_user.id) | 
        (models.Transaction.receiver_id == current_user.id) |
        (models.Transaction.initiated_by_id == current_user.id)
    ).order_by(models.Transaction.timestamp.desc()).limit(10).all()
    
    # Calculate Unread Counts (Optimized: Single Pass or Group By)
    # We need unread counts PER USER (sender/receiver) to show badges on People/Merchants list.
    
    # A. Unread Transactions (Inc. Failed)
    unread_tx_counts = {}
    unread_txs = db.query(models.Transaction.sender_id, func.count(models.Transaction.id))\
        .filter(models.Transaction.receiver_id == current_user.id)\
        .filter(models.Transaction.read_at == None)\
        .group_by(models.Transaction.sender_id).all()
    for uid, count in unread_txs:
        unread_tx_counts[uid] = count
        
    # B. Unread Messages
    unread_msg_counts = {}
    unread_msgs = db.query(models.Message.sender_id, func.count(models.Message.id))\
        .filter(models.Message.receiver_id == current_user.id)\
        .filter(models.Message.read_at == None)\
        .group_by(models.Message.sender_id).all()
    for uid, count in unread_msgs:
        unread_msg_counts[uid] = count

    # C. Unread Payment Requests (Requester is the one we see in list?)
    # Wait, for payment requests, the "Person" is the Requester.
    unread_req_counts = {}
    unread_reqs = db.query(models.PaymentRequest.requester_id, func.count(models.PaymentRequest.id))\
        .filter(models.PaymentRequest.payer_id == current_user.id)\
        .filter(models.PaymentRequest.read_at == None)\
        .group_by(models.PaymentRequest.requester_id).all()
    for uid, count in unread_reqs:
        unread_req_counts[uid] = count
        
    total_unread_global = sum(unread_tx_counts.values()) + sum(unread_msg_counts.values()) + sum(unread_req_counts.values())

    # D. Daily Summary (Rolling 24-hour window ending NOW for real-time display)
    now = datetime.now()
    end_time = now
    start_time = now - timedelta(days=1)
    
    daily_received = db.query(func.sum(models.Transaction.amount)).filter(
        models.Transaction.receiver_id == current_user.id,
        models.Transaction.status == "SUCCESS",
        models.Transaction.timestamp >= start_time,
        models.Transaction.timestamp <= end_time
    ).scalar() or 0.0
    
    daily_sent = db.query(func.sum(models.Transaction.amount)).filter(
        (models.Transaction.sender_id == current_user.id) | (models.Transaction.initiated_by_id == current_user.id),
        models.Transaction.status == "SUCCESS",
        models.Transaction.timestamp >= start_time,
        models.Transaction.timestamp <= end_time
    ).scalar() or 0.0

    # Self Sent: User's own money, initiated by them
    self_sent = db.query(func.sum(models.Transaction.amount)).filter(
        models.Transaction.sender_id == current_user.id,
        (models.Transaction.initiated_by_id == None) | (models.Transaction.initiated_by_id == current_user.id),
        models.Transaction.status == "SUCCESS",
        models.Transaction.timestamp >= start_time,
        models.Transaction.timestamp <= end_time
    ).scalar() or 0.0

    # Circle Sent: Funded by parent but initiated by child, OR vice-versa
    circle_sent = db.query(func.sum(models.Transaction.amount)).filter(
        (
            (models.Transaction.sender_id == current_user.id) & (models.Transaction.initiated_by_id != None) & (models.Transaction.initiated_by_id != current_user.id)
        ) | (
            (models.Transaction.initiated_by_id == current_user.id) & (models.Transaction.sender_id != current_user.id)
        ),
        models.Transaction.status == "SUCCESS",
        models.Transaction.timestamp >= start_time,
        models.Transaction.timestamp <= end_time
    ).scalar() or 0.0

    last_received = db.query(models.Transaction.timestamp).filter(
        models.Transaction.receiver_id == current_user.id,
        models.Transaction.status == "SUCCESS",
        models.Transaction.timestamp >= start_time,
        models.Transaction.timestamp <= end_time
    ).order_by(models.Transaction.timestamp.desc()).first()
    
    last_sent = db.query(models.Transaction.timestamp).filter(
        (models.Transaction.sender_id == current_user.id) | (models.Transaction.initiated_by_id == current_user.id),
        models.Transaction.status == "SUCCESS",
        models.Transaction.timestamp >= start_time,
        models.Transaction.timestamp <= end_time
    ).order_by(models.Transaction.timestamp.desc()).first()

    summary_schema = schemas.DailySummarySchema(
        received_amount=daily_received,
        sent_amount=daily_sent,
        self_sent_amount=self_sent,
        circle_sent_amount=circle_sent,
        start_time=start_time,
        end_time=end_time,
        last_received_at=last_received[0] if last_received else None,
        last_sent_at=last_sent[0] if last_sent else None
    )

    history_list = []
    for t in history_txs:
        # Check manual mapping validity
        history_list.append(schemas.TransactionResponse(
            transaction_id=t.transaction_id,
            sender_upi_id=t.sender.upi_id,
            receiver_upi_id=t.receiver.upi_id,
            sender_name=t.sender.username,
            receiver_name=t.receiver.username,
            sender_full_name=t.sender.full_name,
            receiver_full_name=t.receiver.full_name,
            amount=t.amount,
            status=t.status,
            risk_score=t.risk_score,
            timestamp=t.timestamp,
            sender_mcc=t.sender.mcc,
            receiver_mcc=t.receiver.mcc,
            note=t.note,
            sender_bank_name=t.sender.bank_name,
            receiver_bank_name=t.receiver.bank_name,
            initiated_by_name=t.initiated_by.username if t.initiated_by else None,
            initiated_by_upi=t.initiated_by.upi_id if t.initiated_by else None
        ))

    # 2. Get Recent People (Limit 16)
    # 2. Get Recent People (Limit 16)
    print(f"🔍 Fetching recent people for user {current_user.id}...")
    people_query = text("""
        SELECT u.id, u.username, u.mobile_encrypted, u.email_encrypted, u.upi_id, u.mcc, u.balance
        FROM users u
        JOIN (
            SELECT 
                CASE 
                    WHEN sender_id = :uid THEN receiver_id 
                    WHEN initiated_by_id = :uid THEN receiver_id
                    ELSE sender_id 
                END as other_id,
                MAX(timestamp) as last_tx
            FROM transactions 
            WHERE sender_id = :uid OR receiver_id = :uid OR initiated_by_id = :uid
            GROUP BY other_id
        ) t ON u.id = t.other_id
        WHERE (u.mcc IS NULL OR u.mcc = '' OR u.mcc = '0' OR u.mcc = '00' OR u.mcc = '000' OR u.mcc = '0000') AND u.id != :uid
        ORDER BY t.last_tx DESC
        LIMIT 16
    """)
    people_result = db.execute(people_query, {"uid": current_user.id}).fetchall()
    print(f"✅ Found {len(people_result)} people")

    people_list = []
    for row in people_result:
        try:
            p = schemas.UserLookupResponse(
                id=row.id, 
                username=row.username, 
                mobile_number=security.decrypt_value(row.mobile_encrypted) if row.mobile_encrypted else None,
                upi_id=row.upi_id, 
                mcc=row.mcc,
                balance=row.balance, 
                unread_count=unread_tx_counts.get(row.id, 0) + unread_msg_counts.get(row.id, 0) + unread_req_counts.get(row.id, 0)
            )
            people_list.append(p)
        except Exception as e:
            print(f"⚠️ Error processing person row {row.id}: {e}")

    # 3. Get Recent Merchants (Limit 16)
    print(f"🔍 Fetching recent merchants for user {current_user.id}...")
    merchants_query = text("""
        SELECT u.id, u.username, u.mobile_encrypted, u.email_encrypted, u.upi_id, u.mcc, u.balance
        FROM users u
        JOIN (
            SELECT 
                CASE 
                    WHEN sender_id = :uid THEN receiver_id 
                    WHEN initiated_by_id = :uid THEN receiver_id
                    ELSE sender_id 
                END as other_id,
                MAX(timestamp) as last_tx
            FROM transactions 
            WHERE sender_id = :uid OR receiver_id = :uid OR initiated_by_id = :uid
            GROUP BY other_id
        ) t ON u.id = t.other_id
        WHERE u.mcc IS NOT NULL AND u.mcc != '' AND u.mcc != '0' AND u.mcc != '00' AND u.mcc != '000' AND u.mcc != '0000' AND u.id != :uid
        ORDER BY t.last_tx DESC
        LIMIT 16
    """)
    merchants_result = db.execute(merchants_query, {"uid": current_user.id}).fetchall()
    print(f"✅ Found {len(merchants_result)} merchants")

    merchants_list = []
    for row in merchants_result:
        try:
            m = schemas.UserLookupResponse(
                id=row.id, 
                username=row.username, 
                mobile_number=security.decrypt_value(row.mobile_encrypted) if row.mobile_encrypted else None,
                upi_id=row.upi_id, 
                mcc=row.mcc,
                balance=row.balance,
                unread_count=unread_tx_counts.get(row.id, 0) + unread_msg_counts.get(row.id, 0) + unread_req_counts.get(row.id, 0)
            )
            merchants_list.append(m)
        except Exception as e:
            print(f"⚠️ Error processing merchant row {row.id}: {e}")

    pending_reqs = db.query(models.PaymentRequest).filter(
        models.PaymentRequest.payer_id == current_user.id,
        models.PaymentRequest.status == "pending"
    ).order_by(models.PaymentRequest.timestamp.desc()).all()
    
    pending_list = [_build_payment_request_response(r) for r in pending_reqs]

    # --- Pending UPI Circle Invites ---
    pending_circles_query = db.query(models.UPICircle).filter(
        models.UPICircle.secondary_user_id == current_user.id,
        models.UPICircle.status == "PENDING"
    ).all()
    
    pending_circle_list = []
    for c in pending_circles_query:
        primary = c.primary_user
        secondary = c.secondary_user
        pending_circle_list.append(schemas.UPICircleMemberResponse(
            id=c.id,
            primary_user_upi=primary.upi_id if primary else "",
            primary_user_name=primary.username if primary else "",
            secondary_user_upi=secondary.upi_id if secondary else "",
            secondary_user_name=secondary.username if secondary else "",
            monthly_limit=c.monthly_limit,
            current_monthly_spend=0.0,
            delegation_type=c.delegation_type,
            status=c.status,
            created_at=c.created_at
        ))

    response_data = schemas.HomeAggregateResponse(
        user=current_user,
        history=history_list,
        people=people_list,
        merchants=merchants_list,
        pending_requests=pending_list,
        pending_circle_invites=pending_circle_list,
        total_unread=total_unread_global,
        daily_summary=summary_schema
    )
    
    # Update Cache
    HOME_DATA_CACHE[current_user.id] = (datetime.now(), response_data)
    
    return response_data

@app.post("/notifications/mark-read/{sender_id}")
def mark_conversation_read(
    sender_id: int,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Mark all transactions, messages, and requests from a specific user as READ.
    """
    now = datetime.now()
    
    # 1. Messages
    db.query(models.Message).filter(
        models.Message.sender_id == sender_id,
        models.Message.receiver_id == current_user.id,
        models.Message.read_at == None
    ).update({models.Message.read_at: now})
    
    # 2. Transactions
    db.query(models.Transaction).filter(
        models.Transaction.sender_id == sender_id,
        models.Transaction.receiver_id == current_user.id,
        models.Transaction.read_at == None
    ).update({models.Transaction.read_at: now})
    
    # 3. Payment Requests (Where I am payer, sender is requester)
    db.query(models.PaymentRequest).filter(
        models.PaymentRequest.requester_id == sender_id,
        models.PaymentRequest.payer_id == current_user.id,
        models.PaymentRequest.read_at == None
    ).update({models.PaymentRequest.read_at: now})
    
    db.commit()
    
    # Invalidate Cache
    if current_user.id in HOME_DATA_CACHE:
        del HOME_DATA_CACHE[current_user.id]

    return {"msg": "Marked as read"}

@app.post("/notifications/mark-all-read")
def mark_all_read(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Mark ALL unread items for the current user as READ.
    Used when the app opens to clear all badges.
    """
    now = datetime.now()
    
    # 1. Messages
    db.query(models.Message).filter(
        models.Message.receiver_id == current_user.id,
        models.Message.read_at == None
    ).update({models.Message.read_at: now})
    
    # 2. Transactions
    db.query(models.Transaction).filter(
        models.Transaction.receiver_id == current_user.id,
        models.Transaction.read_at == None
    ).update({models.Transaction.read_at: now})
    
    # 3. Payment Requests
    db.query(models.PaymentRequest).filter(
        models.PaymentRequest.payer_id == current_user.id,
        models.PaymentRequest.read_at == None
    ).update({models.PaymentRequest.read_at: now})
    
    db.commit()
    
    # Invalidate Cache
    if current_user.id in HOME_DATA_CACHE:
        del HOME_DATA_CACHE[current_user.id]

    return {"msg": "All notifications marked as read"}

@app.get("/transactions/history", response_model=list[schemas.TransactionResponse])
def read_history(current_user: models.User = Depends(get_current_user), db: Session = Depends(get_db)):
    # Check Cache
    CACHE_KEY = f"history_{current_user.id}"
    if CACHE_KEY in HOME_DATA_CACHE:
        ts, cached_data = HOME_DATA_CACHE[CACHE_KEY]
        if (datetime.now() - ts).total_seconds() < CACHE_TTL:
            return cached_data

    from sqlalchemy.orm import joinedload
    # Get sent and received
    # OPTIMIZATION: Eager load sender and receiver to prevent N+1 queries
    txs = db.query(models.Transaction).options(
        joinedload(models.Transaction.sender), 
        joinedload(models.Transaction.receiver),
        joinedload(models.Transaction.initiated_by)
    ).filter(
        (models.Transaction.sender_id == current_user.id) | 
        (models.Transaction.initiated_by_id == current_user.id) |
        (
            (models.Transaction.receiver_id == current_user.id) & 
            (models.Transaction.status != "FAILED")
        )
    ).order_by(models.Transaction.timestamp.desc()).all()
    
    # Map to schema manually or rely on ORM if relation is eager loaded. 
    # To be safe with Pydantic and lazy loading:
    results = []
    for t in txs:
        # We need to fetch UPIs provided we have relationships
        results.append(schemas.TransactionResponse(
            transaction_id=t.transaction_id,
            sender_upi_id=t.sender.upi_id,
            receiver_upi_id=t.receiver.upi_id,
            sender_name=t.sender.username,
            receiver_name=t.receiver.username,
            sender_full_name=t.sender.full_name,
            receiver_full_name=t.receiver.full_name,
            amount=t.amount,
            status=t.status,
            risk_score=t.risk_score,
            timestamp=t.timestamp,
            sender_mcc=t.sender.mcc,
            receiver_mcc=t.receiver.mcc,
            note=t.note,
            sender_bank_name=t.sender.bank_name,
            receiver_bank_name=t.receiver.bank_name,
            initiated_by_name=t.initiated_by.username if t.initiated_by else None,
            initiated_by_upi=t.initiated_by.upi_id if t.initiated_by else None
        ))
        
    # Update Cache
    HOME_DATA_CACHE[CACHE_KEY] = (datetime.now(), results)
        
    return results

@app.get("/transactions/recent-people", response_model=list[schemas.UserResponse])
def get_recent_people(
    limit: int = 16,
    current_user: models.User = Depends(get_current_user), 
    db: Session = Depends(get_db)
):
    # Check Cache
    CACHE_KEY = f"people_{current_user.id}_{limit}"
    if CACHE_KEY in HOME_DATA_CACHE:
        ts, cached_data = HOME_DATA_CACHE[CACHE_KEY]
        if (datetime.now() - ts).total_seconds() < CACHE_TTL:
            return cached_data

    # FAST SQL QUERY
    # PEOPLE = MCC is NULL OR MCC is '0000' OR MCC is empty ''
    
    query = text("""
        SELECT u.id, u.username, u.mobile_encrypted, u.email_encrypted, u.upi_id, u.mcc, u.balance
        FROM users u
        JOIN (
            SELECT 
                CASE WHEN sender_id = :uid THEN receiver_id ELSE sender_id END as other_id,
                MAX(timestamp) as last_tx
            FROM transactions 
            WHERE sender_id = :uid OR receiver_id = :uid
            GROUP BY other_id
        ) t ON u.id = t.other_id
        WHERE (u.mcc IS NULL OR u.mcc = '' OR u.mcc = '0' OR u.mcc = '00' OR u.mcc = '000' OR u.mcc = '0000') AND u.id != :uid
        ORDER BY t.last_tx DESC
        LIMIT :limit
    """)
    
    result = db.execute(query, {"uid": current_user.id, "limit": limit}).fetchall()
    
    print(f"DEBUG: get_recent_people for uid={current_user.id} query returned {len(result)} rows")

    # Map raw results back to Pydantic models
    users = []
    for row in result:
        # print(f"DEBUG: Processing person: {row.username} (MCC: {row.mcc})") 
        users.append(models.User(
            id=row.id,
            username=row.username,
            mobile_encrypted=row.mobile_encrypted,
            email_encrypted=row.email_encrypted,
            upi_id=row.upi_id,
            mcc=row.mcc,
            balance=row.balance,
        ))
        
    # Update Cache
    HOME_DATA_CACHE[CACHE_KEY] = (datetime.now(), users)
        
    return users

@app.get("/transactions/recent-merchants", response_model=list[schemas.UserResponse])
def get_recent_merchants(
    limit: int = 16,
    current_user: models.User = Depends(get_current_user), 
    db: Session = Depends(get_db)
):
    # Check Cache
    CACHE_KEY = f"merchants_{current_user.id}_{limit}"
    if CACHE_KEY in HOME_DATA_CACHE:
        ts, cached_data = HOME_DATA_CACHE[CACHE_KEY]
        if (datetime.now() - ts).total_seconds() < CACHE_TTL:
            return cached_data

    # FAST SQL QUERY
    # MERCHANTS = MCC is NOT NULL AND MCC != '0000' AND MCC != ''
    query = text("""
        SELECT u.id, u.username, u.mobile_encrypted, u.email_encrypted, u.upi_id, u.mcc, u.balance
        FROM users u
        JOIN (
            SELECT 
                CASE WHEN sender_id = :uid THEN receiver_id ELSE sender_id END as other_id,
                MAX(timestamp) as last_tx
            FROM transactions 
            WHERE sender_id = :uid OR receiver_id = :uid
            GROUP BY other_id
        ) t ON u.id = t.other_id
        WHERE u.mcc IS NOT NULL AND u.mcc != '' AND u.mcc != '0' AND u.mcc != '00' AND u.mcc != '000' AND u.mcc != '0000' AND u.id != :uid
        ORDER BY t.last_tx DESC
        LIMIT :limit
    """)
    
    result = db.execute(query, {"uid": current_user.id, "limit": limit}).fetchall()
    
    print(f"DEBUG: get_recent_merchants for uid={current_user.id} query returned {len(result)} rows")

    users = []
    for row in result:
        # print(f"DEBUG: Processing merchant: {row.username} (MCC: {row.mcc})")
        users.append(models.User(
            id=row.id,
            username=row.username,
            mobile_encrypted=row.mobile_encrypted,
            email_encrypted=row.email_encrypted,
            upi_id=row.upi_id,
            mcc=row.mcc,
            balance=row.balance,
        ))
        
    # Update Cache
    HOME_DATA_CACHE[CACHE_KEY] = (datetime.now(), users)
        
    return users

@app.post("/messages", response_model=schemas.MessageResponse)
def send_message(
    msg: schemas.MessageCreate,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    receiver = db.query(models.User).filter(models.User.upi_id == msg.receiver_upi_id).first()
    if not receiver:
        raise HTTPException(status_code=404, detail="Receiver not found")
        
    new_msg = models.Message(
        sender_id=current_user.id,
        receiver_id=receiver.id,
        content=msg.content,  # Keep plain for backward compatibility
        encrypted_content=security.encrypt_value(msg.content),  # AES-256 encrypted
        timestamp=datetime.now()
    )
    db.add(new_msg)
    db.commit()
    db.refresh(new_msg)
    
    return schemas.MessageResponse(
        id=new_msg.id,
        sender_upi_id=current_user.upi_id,
        receiver_upi_id=receiver.upi_id,
        content=msg.content,  # Return original content to sender
        timestamp=new_msg.timestamp
    )

@app.get("/transactions/conversation/{target_upi_id}")
def get_conversation(
    target_upi_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    # Find target user
    target_user = db.query(models.User).filter(models.User.upi_id == target_upi_id).first()
    if not target_user:
        raise HTTPException(status_code=404, detail="Target user not found")

    # 1. Fetch Transactions (Optimized)
    txs = db.query(models.Transaction).options(
        joinedload(models.Transaction.sender), 
        joinedload(models.Transaction.receiver),
        joinedload(models.Transaction.initiated_by)
    ).filter(
        (
            ((models.Transaction.sender_id == current_user.id) | (models.Transaction.initiated_by_id == current_user.id)) & 
            ((models.Transaction.receiver_id == target_user.id) | (models.Transaction.initiated_by_id == target_user.id))
        ) | 
        (
            ((models.Transaction.sender_id == target_user.id) | (models.Transaction.initiated_by_id == target_user.id)) & 
            ((models.Transaction.receiver_id == current_user.id) | (models.Transaction.initiated_by_id == current_user.id))
        )
    ).order_by(models.Transaction.timestamp.desc()).limit(50).all()
    
    # 2. Fetch Messages (Optimized)
    msgs = db.query(models.Message).options(
        joinedload(models.Message.sender),
        joinedload(models.Message.receiver)
    ).filter(
        (
            (models.Message.sender_id == current_user.id) & 
            (models.Message.receiver_id == target_user.id)
        ) | 
        (
            (models.Message.sender_id == target_user.id) & 
            (models.Message.receiver_id == current_user.id)
        )
    ).order_by(models.Message.timestamp.desc()).limit(50).all()
    
    combined = []
    
    # Process Transactions
    # Filter visibility logic: Only show if SUCCESS or (FAILED and I am SENDER or INITIATOR)
    for t in txs:
        should_show = False
        if t.status == "SUCCESS":
            should_show = True
        elif t.sender_id == current_user.id or t.initiated_by_id == current_user.id:
            should_show = True
            
        if should_show:
            combined.append({
                "type": "transaction",
                "transaction_id": t.transaction_id,
                "sender_upi_id": t.sender.upi_id,
                "receiver_upi_id": t.receiver.upi_id,
                "amount": t.amount,
                "status": t.status,
                "risk_score": t.risk_score,
                "timestamp": t.timestamp,
                "sender_mcc": t.sender.mcc,
                "receiver_mcc": t.receiver.mcc,
                "note": t.note,
                "initiated_by_name": t.initiated_by.username if t.initiated_by else None,
                "initiated_by_upi": t.initiated_by.upi_id if t.initiated_by else None
            })
            
    # Process Messages
    for m in msgs:
        # Prefer encrypted content if available, otherwise use plain content
        msg_content = m.content
        if m.encrypted_content:
            decrypted = security.decrypt_value(m.encrypted_content, str)
            if decrypted:
                msg_content = decrypted
        
        combined.append({
            "type": "message",
            "id": m.id,
            "sender_upi_id": m.sender.upi_id,
            "receiver_upi_id": m.receiver.upi_id,
            "content": msg_content,
            "timestamp": m.timestamp
        })

    # 3. Fetch Payment Requests between the two users
    payment_requests = db.query(models.PaymentRequest).filter(
        (
            (models.PaymentRequest.requester_id == current_user.id) &
            (models.PaymentRequest.payer_id == target_user.id)
        ) |
        (
            (models.PaymentRequest.requester_id == target_user.id) &
            (models.PaymentRequest.payer_id == current_user.id)
        )
    ).order_by(models.PaymentRequest.timestamp.desc()).limit(50).all()

    for pr in payment_requests:
        combined.append({
            "type": "payment_request",
            "id": pr.id,
            "requester_upi_id": pr.requester.upi_id,
            "payer_upi_id": pr.payer.upi_id,
            "requester_name": pr.requester.username,
            "payer_name": pr.payer.username,
            "amount": pr.amount,
            "status": pr.status,
            "reason": pr.reason,
            "description": pr.description,
            "original_transaction_id": pr.original_transaction_id,
            "timestamp": pr.timestamp,
            "cancelled_by": pr.cancelled_by
        })
        
    # Sort combined list by timestamp DESC (Newest first)
    combined.sort(key=lambda x: x['timestamp'], reverse=True)
        
    return combined


# ═══════════════════════════════════════════════════════════════════════════
# FRAUD REPORTING ENDPOINT (For AI Learning)
# ═══════════════════════════════════════════════════════════════════════════

@app.post("/api/report-fraud", 
          response_model=schemas.FraudReportResponse,
          tags=["Security"],
          summary="Report a fraudulent transaction",
          description="""
Report a suspicious transaction. This helps the AI learn real fraud patterns.

**Reasons:**
- `not_me` - I didn't make this transaction
- `wrong_amount` - Amount is incorrect  
- `unknown_receiver` - I don't know this person
- `other` - Other reason (provide description)
""")
async def report_fraud(
    report: schemas.FraudReportRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    User reports a transaction as fraudulent.
    
    This is GOLD for AI learning:
    1. User reports transaction they didn't authorize
    2. We save it to UserFraudReport table
    3. We also add to FraudEvent table (for AI training)
    4. Next 24h retrain will learn from this
    """
    
    # Validate transaction exists and belongs to user
    transaction = db.query(models.Transaction).filter(
        models.Transaction.transaction_id == report.transaction_id
    ).first()
    
    if not transaction:
        return schemas.FraudReportResponse(
            success=False,
            message="Transaction not found"
        )
    
    # User must be sender or receiver
    if transaction.sender_id != current_user.id and transaction.receiver_id != current_user.id:
        return schemas.FraudReportResponse(
            success=False,
            message="You can only report your own transactions"
        )
    
    # Check if already reported
    existing_report = db.query(models.UserFraudReport).filter(
        models.UserFraudReport.transaction_id == report.transaction_id,
        models.UserFraudReport.user_id == current_user.id
    ).first()
    
    if existing_report:
        return schemas.FraudReportResponse(
            success=False,
            message="You have already reported this transaction"
        )
    
    # Valid reasons
    valid_reasons = ["not_me", "wrong_amount", "unknown_receiver", "other"]
    if report.reason not in valid_reasons:
        return schemas.FraudReportResponse(
            success=False,
            message=f"Invalid reason. Must be one of: {', '.join(valid_reasons)}"
        )
    
    # Create fraud report (for tracking/review)
    # IMPORTANT: is_confirmed_fraud=False means AI won't train on this
    # until an admin confirms it. This prevents false reports from
    # poisoning the AI model.
    fraud_report = models.UserFraudReport(
        user_id=current_user.id,
        transaction_id=report.transaction_id,
        reason=report.reason,
        description=report.description,
        status="pending",  # Needs admin review
        is_confirmed_fraud=False  # NOT auto-confirmed - prevents wrong training
    )
    db.add(fraud_report)
    
    # NOTE: We do NOT add to FraudEvent table automatically anymore.
    # Only confirmed fraud reports should be added to FraudEvent.
    # This happens when admin confirms the report via a separate endpoint.
    # 
    # This protects against users reporting their own transactions
    # as fraud and causing the AI to learn wrong patterns.
    
    db.commit()
    db.refresh(fraud_report)
    
    logger.info(f"🚨 Fraud Report: User {current_user.upi_id} reported {report.transaction_id} - {report.reason}")
    
    return schemas.FraudReportResponse(
        success=True,
        message="Thank you. Your report has been submitted for review.",
        report_id=fraud_report.id
    )



# ═══════════════════════════════════════════════════════════════════════════
# PAYMENT REQUESTS
# ═══════════════════════════════════════════════════════════════════════════

def _is_merchant_user(user: models.User) -> bool:
    """Check if a user is a merchant based on MCC code"""
    if user.mcc is None or user.mcc == "":
        return False
    # Check if all characters are '0'
    if all(c == '0' for c in user.mcc):
        return False
    return True

def _build_payment_request_response(req: models.PaymentRequest) -> schemas.PaymentRequestResponse:
    """Helper to build a consistent PaymentRequestResponse"""
    return schemas.PaymentRequestResponse(
        id=req.id,
        requester_id=req.requester_id,
        requester_upi_id=req.requester.upi_id,
        payer_upi_id=req.payer.upi_id,
        requester_name=req.requester.username,
        payer_name=req.payer.username,
        amount=req.amount,
        status=req.status,
        reason=req.reason,
        description=req.description,
        original_transaction_id=req.original_transaction_id,
        target_upi=req.target_upi,
        circle_id=req.circle_id,
        timestamp=req.timestamp,
        cancelled_by=req.cancelled_by
    )

@app.post("/requests", response_model=schemas.PaymentRequestResponse)
def create_payment_request(
    request_data: schemas.PaymentRequestCreate,
    background_tasks: BackgroundTasks,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Create a new payment request (Ask for money)"""
    
    # Validate Payer
    payer = db.query(models.User).filter(models.User.upi_id == request_data.payer_upi_id).first()
    if not payer:
        raise HTTPException(status_code=404, detail="Payer UPI ID not found")
        
    if payer.id == current_user.id:
        raise HTTPException(status_code=400, detail="Cannot request money from self")
        
    # Validation: Cannot request money from Merchant accounts (use MCC check)
    if _is_merchant_user(payer):
        raise HTTPException(status_code=403, detail="Cannot request money from a Merchant account")

    # Validation: One pending request per transaction
    if request_data.original_transaction_id:
        existing = db.query(models.PaymentRequest).filter(
            models.PaymentRequest.original_transaction_id == request_data.original_transaction_id,
            models.PaymentRequest.status == "pending"
        ).first()
        if existing:
            raise HTTPException(status_code=409, detail="A pending request already exists for this transaction")

    # Create Request
    new_request = models.PaymentRequest(
        requester_id=current_user.id,
        payer_id=payer.id,
        amount=request_data.amount,
        reason=request_data.reason,
        description=request_data.description,
        original_transaction_id=request_data.original_transaction_id,
        status="pending",
        timestamp=datetime.now()
    )
    
    db.add(new_request)
    db.commit()
    db.refresh(new_request)
    
    # Push Notification (Background Task)
    notif_title = "Payment Request"
    notif_body = f"{current_user.username} requested ₹{request_data.amount}"

    if request_data.original_transaction_id:
        notif_title = "Refund Request"
        notif_body = f"{current_user.username} is requesting reverse amount of ₹{request_data.amount}"

    notifications.send_push_notification(
        db,
        user_id=payer.id,
        title=notif_title,
        message=notif_body,
        notif_type="payment_request",
        background_tasks=background_tasks
    )

    db.commit() # Commit the notification

    return _build_payment_request_response(new_request)

@app.post("/requests/{request_id}/cancel", response_model=schemas.PaymentRequestResponse)
def cancel_payment_request(
    request_id: int,
    background_tasks: BackgroundTasks,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Cancel or Decline a payment request"""
    req = db.query(models.PaymentRequest).filter(models.PaymentRequest.id == request_id).first()
    if not req:
        raise HTTPException(status_code=404, detail="Request not found")
        
    # Validation: Only Requester or Payer can cancel
    if req.requester_id != current_user.id and req.payer_id != current_user.id:
        raise HTTPException(status_code=403, detail="Access denied")
        
    if req.status != "pending":
        raise HTTPException(status_code=400, detail="Request is already processed")
         
    # Update Status
    req.status = "cancelled"
    req.updated_at = datetime.now()
    
    # Who cancelled?
    if current_user.id == req.requester_id:
        req.cancelled_by = "requester"  # "Withdrawn"
        notify_user_id = req.payer_id
        notif_title = "Request Cancelled"
        notif_msg = f"{current_user.username} cancelled their payment request for ₹{req.amount}."
    else:
        req.cancelled_by = "payer"  # "Declined"
        notify_user_id = req.requester_id
        notif_title = "Request Declined"
        notif_msg = f"{current_user.username} declined your payment request for ₹{req.amount}."

        # Special logic for Circle rejections: Create a failed transaction record for history
        if req.circle_id:
            try:
                failed_tx_id = f"TXN_FAIL_{int(datetime.now().timestamp()*1000)}"
                new_failed_tx = models.Transaction(
                    transaction_id=failed_tx_id,
                    sender_id=req.payer_id,
                    receiver_id=db.query(models.User).filter(models.User.upi_id == req.target_upi).first().id if req.target_upi else None,
                    initiated_by_id=req.requester_id,
                    amount=req.amount,
                    status="FAILED",
                    risk_score="SAFE", # It wasn't fraud, just parent's choice
                    note=f"Rejected: {req.reason}",
                    timestamp=datetime.now(),
                    ip_hash="CIRCLE_REJECTION" # Mark for audit
                )
                db.add(new_failed_tx)
                
                # Override notification for circle rejection
                notif_msg = f"Your payment request of ₹{req.amount} was declined by the parent."

            except Exception as e:
                print(f"Failed to create circle rejection record: {e}")
        
    # Notify the other party
    notifications.send_push_notification(
        db,
        notify_user_id,
        notif_title,
        notif_msg,
        "payment_cancelled",
        background_tasks=background_tasks
    )

    db.commit()
    
    return _build_payment_request_response(req)

@app.post("/requests/{request_id}/mark-paid", response_model=schemas.PaymentRequestResponse)
def mark_request_paid(
    request_id: int,
    background_tasks: BackgroundTasks,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Mark a payment request as paid (called after successful payment)"""
    req = db.query(models.PaymentRequest).filter(models.PaymentRequest.id == request_id).first()
    if not req:
        raise HTTPException(status_code=404, detail="Request not found")
    
    # Only the payer can mark as paid
    if req.payer_id != current_user.id:
        raise HTTPException(status_code=403, detail="Only the payer can mark a request as paid")
    
    if req.status != "pending":
        raise HTTPException(status_code=400, detail="Request is already processed")
    
    req.status = "paid"
    req.updated_at = datetime.now()

    # Notify the requester
    notifications.send_push_notification(
        db,
        req.requester_id,
        "Request Paid",
        f"{current_user.username} paid your request of ₹{req.amount}.",
        "payment_paid",
        background_tasks=background_tasks
    )

    db.commit()
    
    return _build_payment_request_response(req)

@app.get("/requests/pending", response_model=List[schemas.PaymentRequestResponse])
def get_pending_requests(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Get pending requests where I am the Payer (Received Requests)"""
    requests = db.query(models.PaymentRequest).filter(
        models.PaymentRequest.payer_id == current_user.id,
        models.PaymentRequest.status == "pending"
    ).order_by(models.PaymentRequest.timestamp.desc()).all()
    
    return [_build_payment_request_response(r) for r in requests]

@app.get("/requests/sent", response_model=List[schemas.PaymentRequestResponse])
def get_sent_requests(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Get requests I have sent (where I am the Requester)"""
    requests = db.query(models.PaymentRequest).filter(
        models.PaymentRequest.requester_id == current_user.id
    ).order_by(models.PaymentRequest.timestamp.desc()).all()
    
    return [_build_payment_request_response(r) for r in requests]

@app.get("/requests/{request_id}", response_model=schemas.PaymentRequestResponse)
def get_payment_request(
    request_id: int,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Get a single payment request by ID (for polling status)"""
    req = db.query(models.PaymentRequest).filter(
        models.PaymentRequest.id == request_id,
        (models.PaymentRequest.requester_id == current_user.id) |
        (models.PaymentRequest.payer_id == current_user.id)
    ).first()
    
    if not req:
        raise HTTPException(status_code=404, detail="Request not found")
    
    return _build_payment_request_response(req)

@app.get("/requests/for-transaction/{transaction_id}")
def get_request_for_transaction(
    transaction_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Check if a payment request exists for a specific transaction"""
    req = db.query(models.PaymentRequest).filter(
        models.PaymentRequest.original_transaction_id == transaction_id,
        (models.PaymentRequest.requester_id == current_user.id) |
        (models.PaymentRequest.payer_id == current_user.id)
    ).order_by(models.PaymentRequest.timestamp.desc()).first()
    
    if not req:
        return {"exists": False, "request": None}
    
    return {
        "exists": True,
        "request": _build_payment_request_response(req)
    }


# ═══════════════════════════════════════════════════════════════════════════
# NOTIFICATIONS ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════════

@app.get("/notifications", response_model=List[schemas.NotificationResponse])
def get_notifications(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Fetch all notifications for the current user"""
    return db.query(models.Notification).filter(
        models.Notification.user_id == current_user.id
    ).order_by(models.Notification.timestamp.desc()).limit(50).all()

@app.post("/notifications/read-all")
def mark_all_notifications_read(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Mark all notifications as read"""
    db.query(models.Notification).filter(
        models.Notification.user_id == current_user.id,
        models.Notification.is_read == False
    ).update({"is_read": True})
    db.commit()
    return {"success": True}


# ═══════════════════════════════════════════════════════════════════════════
# ADMIN & SYSTEM ENDPOINTS (The "Audit Trail")
# ═══════════════════════════════════════════════════════════════════════════

@app.post("/api/admin/confirm-fraud", tags=["Admin"])
def confirm_fraud_report(
    req: schemas.FraudConfirmationRequest,
    db: Session = Depends(get_db)
):
    """
    ADMIN ONLY: Confirm a user's fraud report as valid.
    This feeds the "Brain" and improves the AI model.
    """
    report = db.query(models.UserFraudReport).filter(models.UserFraudReport.id == req.report_id).first()
    if not report:
        raise HTTPException(status_code=404, detail="Report not found")
        
    report.status = "confirmed" if req.is_fraud else "dismissed"
    report.is_confirmed_fraud = req.is_fraud
    
    if req.is_fraud:
        # Find the original transaction
        tx = db.query(models.Transaction).filter(models.Transaction.transaction_id == report.transaction_id).first()
        if tx:
            # Add to FraudEvent table so the AI learns from it during next retrain
            fraud_engine.record_fraud_event(
                db, 
                user_id=tx.sender_id,
                transaction_id=tx.transaction_id,
                amount=tx.amount,
                ai_score=-1.0, # Definitely fraud
                rule_violation="USER_CONFIRMED_FRAUD",
                is_blocked=True
            )
    
    db.commit()
    return {"success": True, "status": report.status}

@app.get("/api/admin/reveal-audit/{transaction_id}", tags=["Admin"])
def reveal_transaction_audit(
    transaction_id: str,
    db: Session = Depends(get_db)
):
    """
    ADMIN ONLY: Decrypt the secure IP audit trail for a transaction.
    Used for Cybercrime investigations.
    """
    tx = db.query(models.Transaction).filter(models.Transaction.transaction_id == transaction_id).first()
    if not tx:
        raise HTTPException(status_code=404, detail="Transaction not found")
        
    if not tx.ip_encrypted:
        return {"transaction_id": transaction_id, "ip_address": "N/A (No IP logged)"}
        
    try:
        ip_addr = security.decrypt_value(tx.ip_encrypted)
        return {
            "transaction_id": transaction_id,
            "ip_address": ip_addr,
            "decrypted_at": datetime.now().isoformat()
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Decryption failed: {str(e)}")


@app.post("/users/contacts/sync", response_model=schemas.ContactSyncResponse)
def sync_contacts(
    req: schemas.ContactSyncRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
    accept_language: str = Header("en", alias="Accept-Language")
):
    """
    Sync mobile contacts to the Trust Graph.
    If a contact is already a registered user, mark them as 'Known' in the trust graph.
    This reduces friction (F7 warnings) when paying friends for the first time.
    """
    import security
    
    contacts = req.contacts
    synced_count = 0
    new_links = 0
    
    # 1. Normalize and Hash all incoming phone numbers for search
    hashed_numbers = set()
    for phone in contacts:
        # Simple normalization: keep digits only
        normalized = "".join(filter(str.isdigit, phone))
        if len(normalized) >= 10:
            # Check for multiple variations to match common registration formats
            # 1. The full normalized number (e.g. 918888888888)
            hashed_numbers.add(security.hash_value(normalized))
            
            # 2. Just the last 10 digits (e.g. 8888888888)
            last_10 = normalized[-10:]
            hashed_numbers.add(security.hash_value(last_10))
            
            # 3. Add 91 prefix if not present (Indian standard)
            if not normalized.startswith("91"):
                hashed_numbers.add(security.hash_value("91" + last_10))
    
    if not hashed_numbers:
        return {
            "synced_count": 0,
            "new_trust_links": 0,
            "message": get_text("no_contacts", accept_language)
        }
        
    # 2. Find all registered users matching these phone numbers
    matching_users = db.query(models.User).filter(
        models.User.mobile_hash.in_(list(hashed_numbers))
    ).all()
    
    synced_count = len(matching_users)
    
    # 3. Upsert Trust Graph entries
    for target_user in matching_users:
        if target_user.id == current_user.id:
            continue 
            
        trust_entry = db.query(models.UserTrustGraph).filter(
            models.UserTrustGraph.user_id == current_user.id,
            models.UserTrustGraph.trusted_user_id == target_user.id
        ).first()
        
        if trust_entry:
            if not trust_entry.is_contact:
                trust_entry.is_contact = True
                trust_entry.trust_score = max(trust_entry.trust_score, 10.0)
        else:
            new_trust = models.UserTrustGraph(
                user_id=current_user.id,
                trusted_user_id=target_user.id,
                trust_score=10.0, 
                is_contact=True,
                last_interaction_at=datetime.now()
            )
            db.add(new_trust)
            new_links += 1
            
    db.commit()
    
    return {
        "synced_count": synced_count,
        "new_trust_links": new_links,
        "message": get_text("contacts_synced", accept_language, count=synced_count, links=new_links)
    }


# ═══════════════════════════════════════════════════════════════════════════
# COMPLAINT & FRAUD MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════

@app.post("/complaints")
def submit_complaint(
    complaint: schemas.ComplaintCreate,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
    accept_language: str = Header("en", alias="Accept-Language")
):
    try:
        # 1. Deduplication check — reject duplicates with friendly message
        existing = db.query(models.UserFraudReport).filter(
            models.UserFraudReport.user_id == current_user.id,
            models.UserFraudReport.transaction_id == complaint.transaction_id
        ).first()
        
        if existing:
            raise HTTPException(
                status_code=409,
                detail=get_text("complaint_duplicate", accept_language)
            )

        # 2. Get reported user from UPI
        reported_user = db.query(models.User).filter(
            models.User.upi_id == complaint.reported_user_upi
        ).first()
        
        # 3. Create new report
        new_report = models.UserFraudReport(
            user_id=current_user.id,
            reported_user_id=reported_user.id if reported_user else None,
            transaction_id=complaint.transaction_id,
            sender_name=complaint.sender_name,
            sender_upi_id=complaint.sender_upi_id,
            sender_bank=complaint.sender_bank,
            receiver_name=complaint.receiver_name,
            receiver_upi_id=complaint.receiver_upi_id,
            receiver_bank=complaint.receiver_bank,
            transaction_date=complaint.transaction_date,
            transaction_time=complaint.transaction_time,
            transaction_amount=complaint.transaction_amount,
            payment_through=complaint.payment_through,
            reason=complaint.reason,
            description=complaint.description,
            status="pending"
        )
        
        db.add(new_report)
        db.commit()
        db.refresh(new_report)
        
        return {
            "success": True,
            "id": new_report.id,
            "message": get_text("complaint_success", accept_language)
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"submit_complaint error: {e}")
        import traceback
        traceback.print_exc()
        db.rollback()
        raise HTTPException(status_code=500, detail=f"Internal error: {str(e)}")

@app.get("/complaints/check/{transaction_id}", response_model=schemas.ComplaintCheckResponse)
def check_complaint(
    transaction_id: str,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db),
    accept_language: str = Header("en", alias="Accept-Language")
):
    """Check if the user has already reported this transaction"""
    existing = db.query(models.UserFraudReport).filter(
        models.UserFraudReport.user_id == current_user.id,
        models.UserFraudReport.transaction_id == transaction_id
    ).first()
    
    if existing:
        return {
            "exists": True,
            "status": existing.status,
            "message": get_text("complaint_duplicate", accept_language)
        }
    
    return {
        "exists": False,
        "status": None,
        "message": get_text("complaint_not_found", accept_language)
    }

def get_current_admin(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate admin credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = auth.jwt.decode(token, auth.SECRET_KEY, algorithms=[auth.ALGORITHM])
        username: str = payload.get("sub")
        is_admin_token = payload.get("is_admin", False)
        if username is None or not is_admin_token:
            raise credentials_exception
    except auth.JWTError:
        raise credentials_exception
    
    admin = db.query(models.AdminUser).filter(models.AdminUser.username == username).first()
    if admin is None:
        raise credentials_exception
    return admin

@app.post("/admin/login", response_model=schemas.Token)
def admin_login(form_data: schemas.AdminLogin, db: Session = Depends(get_db)):
    admin = db.query(models.AdminUser).filter(models.AdminUser.username == form_data.username).first()
    if not admin or not auth.verify_password(form_data.password, admin.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect admin username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    access_token = auth.create_access_token(
        data={"sub": admin.username, "is_admin": True}
    )
    return {
        "access_token": access_token,
        "token_type": "bearer",
        "expires_in": auth.ACCESS_TOKEN_EXPIRE_MINUTES * 60
    }

@app.get("/admin/complaints", response_model=List[schemas.ComplaintResponse])
def get_complaints(
    db: Session = Depends(get_db),
    admin: models.AdminUser = Depends(get_current_admin)
):
    return db.query(models.UserFraudReport).options(joinedload(models.UserFraudReport.resolved_by)).order_by(models.UserFraudReport.timestamp.desc()).all()

@app.put("/admin/complaints/{report_id}/verdict")
async def set_complaint_verdict(
    report_id: int,
    verdict: schemas.ComplaintVerdictRequest,
    db: Session = Depends(get_db),
    admin: models.AdminUser = Depends(get_current_admin)
):
    report = db.query(models.UserFraudReport).filter(models.UserFraudReport.id == report_id).first()
    if not report:
        raise HTTPException(status_code=404, detail="Report not found")
        
    if report.status != "pending":
         raise HTTPException(status_code=400, detail=f"Report already {report.status} by {report.resolved_by.username if report.resolved_by else 'another admin'}")

    # Update report status
    report.status = verdict.status # "confirmed_fraud" or "dismissed"
    report.reviewed_at = datetime.now()
    report.resolved_by_admin_id = admin.id
    
    # If confirmed fraud, automatically flag the reported user
    if verdict.status == "confirmed_fraud" and report.reported_user_id:
        user = db.query(models.User).filter(models.User.id == report.reported_user_id).first()
        if user:
            user.is_fraud = True
            # Log this action
            log = models.AdminActionLog(
                admin_id=admin.id,
                target_user_id=user.id,
                action_type="flag_fraud"
            )
            db.add(log)
            
    db.commit()
    
    # Broadcast update to all admins
    await manager.broadcast({"type": "EVENT_COMPLAINT_RESOLVED", "id": report_id, "admin": admin.username})
    
    return {"status": "success", "verdict": verdict.status}

@app.put("/admin/users/{user_id}/toggle-fraud")
async def toggle_user_fraud_status(
    user_id: int,
    status: schemas.UserFraudStatusToggle,
    db: Session = Depends(get_db),
    admin: models.AdminUser = Depends(get_current_admin)
):
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
        
    user.is_fraud = status.is_fraud
    
    # Log the action
    log = models.AdminActionLog(
        admin_id=admin.id,
        target_user_id=user.id,
        action_type="flag_fraud" if status.is_fraud else "unflag_safe"
    )
    db.add(log)
    db.commit()
    
    # Broadcast update to all admins
    await manager.broadcast({"type": "EVENT_USER_TOGGLED", "id": user_id, "is_fraud": user.is_fraud, "admin": admin.username})
    
    return {"status": "success", "is_fraud": user.is_fraud}

@app.get("/admin/users", response_model=List[schemas.UserAdminResponse])
def list_users(
    db: Session = Depends(get_db),
    admin: models.AdminUser = Depends(get_current_admin)
):
    users = db.query(models.User).all()
    
    # Enrich users with the last audit log
    for user in users:
        last_log = db.query(models.AdminActionLog)\
            .filter(models.AdminActionLog.target_user_id == user.id)\
            .order_by(models.AdminActionLog.timestamp.desc())\
            .first()
        
        if last_log:
            user.last_action_by = last_log.admin.username
            user.last_action_at = last_log.timestamp
            
    return users

@app.get("/admin/stats")
def get_admin_stats(
    db: Session = Depends(get_db),
    admin: models.AdminUser = Depends(get_current_admin)
):
    total_complaints = db.query(models.UserFraudReport).count()
    pending_complaints = db.query(models.UserFraudReport).filter(models.UserFraudReport.status == "pending").count()
    confirmed_fraud = db.query(models.UserFraudReport).filter(models.UserFraudReport.status == "confirmed_fraud").count()
    
    total_users = db.query(models.User).count()
    flagged_users = db.query(models.User).filter(models.User.is_fraud == True).count()
    
    # Growth check (Real-time data enabled)
    from datetime import datetime
    today = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
    new_users_today = db.query(models.User).filter(models.User.created_at >= today).count()
    
    return {
        "complaints": {
            "total": total_complaints,
            "pending": pending_complaints,
            "confirmed": confirmed_fraud
        },
        "users": {
            "total": total_users,
            "flagged": flagged_users,
            "new_today": new_users_today
        }
    }

@app.get("/admin/audit-logs")
def get_audit_logs(
    db: Session = Depends(get_db),
    admin: models.AdminUser = Depends(get_current_admin)
):
    logs = db.query(models.AdminActionLog).order_by(models.AdminActionLog.timestamp.desc()).limit(100).all()
    
    result = []
    for log in logs:
        result.append({
            "id": log.id,
            "admin": log.admin.username,
            "target": log.target_user.full_name or log.target_user.username,
            "action": log.action_type,
            "timestamp": log.timestamp
        })
    return result

from fastapi.responses import HTMLResponse

@app.get("/admin-panel", response_class=HTMLResponse)
def get_admin_panel():
    # Note: browser access won't have the header unless requested via JS
    # We serve the page, and the JS should handle the token
    with open("admin.html", "r") as f:
        return f.read()

@app.post("/chatbot")
def chat_with_bot(
    req: schemas.ChatbotRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    try:
        import dotenv
        dotenv.load_dotenv(override=True)
        
        api_key = os.getenv("GEMINI_API_KEY", "").strip()
        if not api_key:
            raise HTTPException(status_code=500, detail="Gemini API key not configured")
        
        genai.configure(api_key=api_key)
        
        system_instruction = (
            "You are the Cyber Help Chatbot for ZaferPay. Your primary job is to assist users with "
            "UPI-related fraud complaints, transaction issues, and cybercrime reporting. "
            "You MUST gracefully and politely answer common greetings (like 'hi', 'hello', 'good morning', etc.). "
            "However, you MUST strictly refuse to answer ANY questions that are not related to UPI, "
            "banking, transactions, cyber fraud, or your own basic capabilities. If a user asks a non-related "
            "question, apologize politely and state that you can only assist with UPI and fraud-related queries."
        )
        
        model = genai.GenerativeModel("gemini-2.5-flash", system_instruction=system_instruction) # Attempting to use the flash model from models.txt
        
        formatted_history = []
        for msg in req.history:
            role = "model" if msg.get("role") == "assistant" else "user"
            formatted_history.append({"role": role, "parts": [msg.get("content", "")]})
            
        chat = model.start_chat(history=formatted_history)
        response = chat.send_message(req.message)
        
        return {"reply": response.text}
    except Exception as e:
        print(f"Chatbot error: {e}")
        import traceback
        traceback.print_exc()
        
        error_msg = str(e)
        if "429" in error_msg or "ResourceExhausted" in error_msg or "Quota exceeded" in error_msg:
             return {"reply": "I'm receiving too many requests right now and have reached my limit. Please try again in about a minute!"}
             
        raise HTTPException(status_code=500, detail="Failed to process chatbot request")

# ═══════════════════════════════════════════════════════════════════════════
# UPI CIRCLE ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════════

@app.post("/circle/invite", tags=["UPI Circle"])
def invite_to_circle(
    req: schemas.UPICircleInviteRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Primary User invites a Secondary User to join their circle"""
    # Find secondary user
    secondary_user = db.query(models.User).filter(models.User.upi_id == req.secondary_upi_id).first()
    if not secondary_user:
        raise HTTPException(status_code=404, detail="Secondary user not found")
        
    # NPCI Rule: Child accounts (no bank account) cannot invite others
    is_child = current_user.bank_account is None
    if is_child:
        raise HTTPException(status_code=403, detail="Child accounts cannot invite others to a UPI Circle.")

    if secondary_user.id == current_user.id:
        raise HTTPException(status_code=400, detail="Cannot invite yourself to a circle")

    # RESTRICTION: Only users WITHOUT a bank account (child accounts) can be invited
    if secondary_user.bank_account is not None:
        raise HTTPException(
            status_code=400, 
            detail="User already has a bank account. UPI Circle is only for users without a bank account (Child Accounts)."
        )

    # NPCI Rule: Max 5 members per Primary User
    active_members_count = db.query(models.UPICircle).filter(
        models.UPICircle.primary_user_id == current_user.id,
        models.UPICircle.status.in_(["ACTIVE", "PENDING"])
    ).count()
    if active_members_count >= 5:
        raise HTTPException(status_code=400, detail="You can have a maximum of 5 members in your UPI Circle")

    # NPCI Rule: Secondary User can only join one circle at a time
    joined_already = db.query(models.UPICircle).filter(
        models.UPICircle.secondary_user_id == secondary_user.id,
        models.UPICircle.status == "ACTIVE"
    ).first()
    if joined_already:
        raise HTTPException(status_code=400, detail="This user is already a member of another UPI Circle")

    # Check if already exists
    existing = db.query(models.UPICircle).filter(
        models.UPICircle.primary_user_id == current_user.id,
        models.UPICircle.secondary_user_id == secondary_user.id
    ).first()
    
    if existing:
        if existing.status == "ACTIVE":
            raise HTTPException(status_code=400, detail="User is already an active member of your circle")
        # Reuse existing pending/revoked record
        existing.status = "PENDING"
        existing.monthly_limit = req.monthly_limit
        existing.delegation_type = req.delegation_type
        # Notify secondary user about re-invite
        notifications.send_push_notification(
            db,
            secondary_user.id,
            "UPI Circle Invitation",
            f"{current_user.username} has invited you to join their UPI Circle. Accept to spend from their account.",
            "circle_invite"
        )
        db.commit()
        
        # Invalidate Cache
        clear_home_cache(current_user.id)
        clear_home_cache(secondary_user.id)
        
        return {"msg": "Invitation sent successfully"}

    # Create new circle invitation
    new_invite = models.UPICircle(
        primary_user_id=current_user.id,
        secondary_user_id=secondary_user.id,
        monthly_limit=req.monthly_limit,
        delegation_type=req.delegation_type,
        status="PENDING"
    )
    db.add(new_invite)
    db.commit()
    
    # Notify secondary user
    notifications.send_push_notification(
        db, 
        secondary_user.id,
        "UPI Circle Invitation",
        f"{current_user.username} has invited you to join their UPI Circle. Accept to spend from their account.",
        "circle_invite"
    )
    db.commit()  # Commit the notification
    
    # Invalidate Cache
    clear_home_cache(current_user.id)
    clear_home_cache(secondary_user.id)
    
    return {"msg": "Invitation sent successfully"}

@app.post("/circle/respond", tags=["UPI Circle"])
def respond_to_circle_invite(
    req: schemas.UPICircleResponseRequest,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Secondary User accepts or rejects the invitation"""
    invite = db.query(models.UPICircle).filter(
        models.UPICircle.id == req.invitation_id,
        models.UPICircle.secondary_user_id == current_user.id
    ).first()
    
    if not invite:
        raise HTTPException(status_code=404, detail="Invitation not found")
        
    if req.action == "ACCEPT":
        # NPCI Rule Check again: Secondary User can only join one circle at a time
        already_active = db.query(models.UPICircle).filter(
            models.UPICircle.secondary_user_id == current_user.id,
            models.UPICircle.status == "ACTIVE"
        ).first()
        if already_active:
             raise HTTPException(status_code=400, detail="You are already a member of another UPI Circle. Leave that circle to join this one.")

        invite.status = "ACTIVE"
        msg = "Invitation accepted"
        # Notify primary user
        notifications.send_push_notification(
            db,
            invite.primary_user_id,
            "Invitation Accepted",
            f"{current_user.username} is now a member of your UPI Circle.",
            "circle_active"
        )
    else:
        invite.status = "REVOKED"
        msg = "Invitation rejected"
        # Notify primary user
        notifications.send_push_notification(
            db,
            invite.primary_user_id,
            "Invitation Declined",
            f"{current_user.username} declined your UPI Circle invitation.",
            "circle_rejected"
        )

    db.commit()
    
    # Invalidate Cache
    clear_home_cache(current_user.id)
    clear_home_cache(invite.primary_user_id)
    
    return {"msg": msg}

@app.get("/circle/status", response_model=schemas.UPICircleStatusResponse, tags=["UPI Circle"])
def get_circle_status(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Fetch all circles where user is either Primary or Secondary"""
    my_circles = db.query(models.UPICircle).filter(models.UPICircle.primary_user_id == current_user.id).all()
    joined_circles = db.query(models.UPICircle).filter(
        models.UPICircle.secondary_user_id == current_user.id,
        models.UPICircle.status == "ACTIVE"
    ).all()
    
    def format_circle(c):
        return schemas.UPICircleMemberResponse(
            id=c.id,
            primary_user_upi=c.primary_user.upi_id,
            primary_user_name=c.primary_user.username,
            secondary_user_upi=c.secondary_user.upi_id,
            secondary_user_name=c.secondary_user.username,
            monthly_limit=c.monthly_limit,
            current_monthly_spend=c.current_monthly_spend,
            delegation_type=c.delegation_type,
            status=c.status,
            created_at=c.created_at,
            last_spent_at=c.last_spent_at
        )

    return {
        "my_circles": [format_circle(c) for c in my_circles],
        "joined_circles": [format_circle(c) for c in joined_circles]
    }

@app.put("/circle/update")
def update_circle(
    req: schemas.UPICircleUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Update circle member configuration (limit, delegation mode, or parent account)"""
    # Only the parent (primary user) can update circle settings
    circle = db.query(models.UPICircle).filter(
        models.UPICircle.id == req.circle_id,
        models.UPICircle.primary_user_id == current_user.id
    ).first()
    
    if not circle:
        raise HTTPException(status_code=404, detail="Circle member not found or access denied")
        
    if req.new_limit is not None:
        circle.monthly_limit = req.new_limit
        
    if req.delegation_type is not None:
        circle.delegation_type = req.delegation_type
        
    if req.primary_user_id is not None:
        # Validate that the new primary_user_id belongs to the same person (mobile)
        new_primary = db.query(models.User).filter(models.User.id == req.primary_user_id).first()
        if not new_primary or new_primary.mobile_hash != current_user.mobile_hash:
            raise HTTPException(status_code=403, detail="New parent account must belong to you")
        circle.primary_user_id = req.primary_user_id

    db.commit()

    # Invalidate child's cache so they see updated settings immediately
    clear_home_cache(circle.secondary_user_id)

    # Send notification to the secondary user (child)
    try:
        change_desc = []
        if req.new_limit is not None:
            change_desc.append(f"limit changed to ₹{req.new_limit}")
        if req.delegation_type is not None:
            change_desc.append(f"access mode changed to {req.delegation_type}")
        
        if change_desc:
            desc_text = " and ".join(change_desc)
            notifications.send_push_notification(
                db,
                user_id=circle.secondary_user_id,
                title="UPI Circle Updated",
                message=f"Your UPI Circle {desc_text} by {current_user.full_name or current_user.username}",
                notif_type="circle_update"
            )
            db.commit() # Commit the notification
    except Exception as e:
        logger.error(f"Failed to send circle update notification: {e}")

    return {
        "msg": "Circle configuration updated successfully", 
        "monthly_limit": circle.monthly_limit,
        "delegation_type": circle.delegation_type,
        "primary_user_id": circle.primary_user_id
    }

@app.delete("/circle/remove/{circle_id}", tags=["UPI Circle"])
def remove_circle_member(
    circle_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(get_current_user)
):
    """Primary User removes/revokes a secondary user from their circle"""
    circle = db.query(models.UPICircle).filter(
        models.UPICircle.id == circle_id,
        models.UPICircle.primary_user_id == current_user.id
    ).first()
    
    if not circle:
        raise HTTPException(status_code=404, detail="Circle member not found")
        
    if circle.status == "REVOKED":
        raise HTTPException(status_code=400, detail="Member is already removed")

    circle.status = "REVOKED"
    db.commit()
    
    # Notify secondary user
    notifications.send_push_notification(
        db,
        circle.secondary_user_id,
        "UPI Circle Access Revoked",
        f"Your access to {current_user.username}'s UPI Circle has been revoked.",
        "circle_revoked"
    )
    
    return {"msg": "Member removed successfully"}

# ═══════════════════════════════════════════════════════════════════════════
# END OF FILE
# ═══════════════════════════════════════════════════════════════════════════
