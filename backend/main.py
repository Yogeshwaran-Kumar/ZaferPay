from fastapi import FastAPI, Depends, HTTPException, status, Header, Request
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy.orm import Session
from sqlalchemy import text
from datetime import timedelta, datetime
import models, schemas, auth, database, fraud_engine, security


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

app = FastAPI(title="Application-2 Mock Bank")

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# Add CORS middleware to allow connections from mobile apps
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allow all origins for development
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Create Database Tables
models.Base.metadata.create_all(bind=database.engine)

# Seed data removed - use import_mock_users.py for population

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
    if user.device_id_hash:
        token_device_hash = security.hash_value(token_device_id)
        if token_device_hash != user.device_id_hash:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Logged in on another device",
                headers={"WWW-Authenticate": "Bearer"},
            )
    
    # Update last_active_at conservatively (max once per minute) to reduce DB writes
    now = datetime.utcnow()
    if not user.last_active_at or (now - user.last_active_at).total_seconds() > 60:
        user.last_active_at = now
        db.commit()
    
    # Refresh user to ensure latest state is returned
    # db.refresh(user) # Not strictly needed if we just committed, but good for consistency if fields changed
        
    return user

@app.post("/token", response_model=schemas.Token)
@limiter.limit("5/minute")
def login_for_access_token(
    request: Request,
    form_data: OAuth2PasswordRequestForm = Depends(), 
    db: Session = Depends(get_db),
    x_device_id: str = Header(None),
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

    if not user or not auth.verify_password(form_data.password, user.hashed_password):
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
                        "message": "already_logged_in",
                        "info": "You are currently logged in on another device. To continue on this device, you must logout from the other device."
                    },
                )
            # Force logout from other device - update device_id automatically below
        
        # Update device_id (either first login or force logout)
        user.device_id_hash = x_device_hash
        user.device_id_encrypted = security.encrypt_value(x_device_id)  # AES-256 encrypted
        user.last_active_at = datetime.utcnow()  # Mark as active now
        db.commit()

    # Record Login History (New Feature)
    try:
        if x_device_id:
            # Check if this device logged in very recently (e.g. last 5 seconds) to avoid dupes on retries
            # but generally we want to log every login session.
            
            client_ip = get_real_ip(request)
            
            login_record = models.LoginHistory(
                user_id=user.id,
                # Device ID: SECURE - Hash + Encrypt only
                device_id_hash=security.hash_value(x_device_id),
                device_id_encrypted=security.encrypt_value(x_device_id),
                login_time=datetime.utcnow(),
                # IP: SECURE - Hash + Encrypt only
                ip_hash=security.hash_value(client_ip) if client_ip else None,
                ip_encrypted=security.encrypt_value(client_ip) if client_ip else None
            )
            db.add(login_record)
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
# REFRESH TOKEN ENDPOINT - Get new access token using refresh token
# ═══════════════════════════════════════════════════════════════════════════
@app.post("/auth/refresh")
def refresh_token(
    refresh_token: str = Header(..., alias="X-Refresh-Token"),
    db: Session = Depends(get_db)
):
    """
    Token Rotation: Exchange refresh token for new access token
    
    This allows the app to get a new access token without re-entering PIN.
    The refresh token is valid for 7 days.
    """
    payload = auth.verify_refresh_token(refresh_token)
    if not payload:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired refresh token"
        )
    
    username = payload.get("sub")
    device_id = payload.get("device_id")
    
    # Verify user still exists
    user = db.query(models.User).filter(models.User.username == username).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
    # Create new access token
    new_access_token = auth.create_access_token(
        data={"sub": username, "device_id": device_id}
    )
    
    return {
        "access_token": new_access_token,
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
        
        # Check if PIN is set
        if not user.hashed_password or user.hashed_password == "NULL":
            return {
                "exists": True, 
                "status": "new", 
                "upi_id": user.upi_id,
                "has_device_conflict": False
            }
        
        # Existing user with PIN - Check for device conflict
        has_device_conflict = False
        if x_device_id:
            x_device_hash = security.hash_value(x_device_id)
            if user.device_id_hash and user.device_id_hash != x_device_hash:
                has_device_conflict = True
                print(f"Device conflict: {user.username} logged in on another device")
        
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

@app.post("/auth/register", response_model=schemas.UserResponse)
def register_user(
    user: schemas.UserRegister,
    db: Session = Depends(get_db)
):
    # Normalize mobile
    normalized_mobile = ''.join(filter(str.isdigit, user.mobile_number)) if user.mobile_number else None
    
    # Check if user exists (check username OR mobile hash)
    # Note: We check mobile_hash of normalized version
    mobile_hash = security.hash_value(normalized_mobile) if normalized_mobile else None
    
    db_user = db.query(models.User).filter(
        (models.User.username == user.username) | 
        (models.User.mobile_hash == mobile_hash if mobile_hash else False)
    ).first()
    
    if db_user:
        raise HTTPException(status_code=400, detail="Username or Mobile already registered")
    
    # Generate default UPI ID if not provided
    # Fallback to username instead of specific suffix
    new_upi = user.username
    
    new_user = models.User(
        username=user.username,
        # Mobile: SECURE - Hash + Encrypt only (no plain text)
        mobile_hash=mobile_hash,
        mobile_encrypted=security.encrypt_value(normalized_mobile) if normalized_mobile else None,
        # Email: SECURE - Hash + Encrypt only (no plain text)
        email_hash=security.hash_value(user.email) if user.email else None,
        email_encrypted=security.encrypt_value(user.email) if user.email else None,
        # UPI ID (shareable - kept plain)
        upi_id=new_upi,
        upi_id_hash=security.hash_value(new_upi),
        balance=1000.0, # Sign up bonus?
        hashed_password=None # No PIN set yet
    )
    
    # Initialize profiles
    db.add(new_user)
    db.commit() # Commit to get ID
    db.refresh(new_user)
    
    s_prof = models.SenderProfile(user_id=new_user.id)
    r_prof = models.ReceiverProfile(user_id=new_user.id)
    db.add(s_prof)
    db.add(r_prof)
    db.commit()
    
    return new_user

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
            upi_id_hash=security.hash_value(upi_id),
            balance=1000.0, # Welcome Bonus
            hashed_password=auth.get_password_hash(req.pin)
        )
        db.add(new_user)
        db.commit()
        db.refresh(new_user)
        
        # Initialize profiles
        s_prof = models.SenderProfile(user_id=new_user.id)
        r_prof = models.ReceiverProfile(user_id=new_user.id)
        db.add(s_prof)
        db.add(r_prof)
        db.commit()
        
        return {"msg": "User created and PIN set successfully"}
        
    # Existing user -> Update PIN
    user.hashed_password = auth.get_password_hash(req.pin)
    db.commit()
    return {"msg": "PIN set successfully"}

@app.post("/logout")
def logout(current_user: models.User = Depends(get_current_user), db: Session = Depends(get_db)):
    # Clear device_id and last_active_at to allow login from another device
    # For logout audit, we might need the current device ID? 
    # Usually passed in header, but we can rely on current_user state if we trust they match (which get_current_user checks)
    
    # We can try to decrypt the stored device ID for logging if needed, or just log the hash
    stored_device_hash = current_user.device_id_hash
    
    # Update Login History: Mark session as ended
    try:
        if stored_device_hash:
            active_history = db.query(models.LoginHistory).filter(
                models.LoginHistory.user_id == current_user.id,
                models.LoginHistory.device_id_hash == stored_device_hash,
                models.LoginHistory.is_active == True
            ).first()
            
            if active_history:
                active_history.logout_time = datetime.utcnow()
                active_history.is_active = False
                db.add(active_history)
    except Exception as e:
        print(f"Error updating logout history: {e}")

    current_user.device_id_hash = None
    current_user.device_id_encrypted = None
    current_user.last_active_at = None
    db.commit()
    print(f"User {current_user.username} logged out")
    return {
        "msg": "Successfully logged out",
        "username": current_user.username,
        "device_cleared": True
    }

@app.get("/users/me", response_model=schemas.UserResponse)
def read_users_me(current_user: models.User = Depends(get_current_user)):
    return current_user

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
            mobile_number=None, # External user
            email=None,
            upi_id=upi_id,
            balance=0.0,
            hashed_password=None
        )
        db.add(user)
        try:
            db.commit()
            db.refresh(user)
            
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

@app.get("/users/history/login", response_model=list[schemas.LoginHistoryResponse])
def get_login_history(current_user: models.User = Depends(get_current_user), db: Session = Depends(get_db)):
    history = db.query(models.LoginHistory).filter(
        models.LoginHistory.user_id == current_user.id
    ).order_by(models.LoginHistory.login_time.desc()).all()
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

@app.put("/users/me/change-pin")
def change_pin(
    req: schemas.ChangePinRequest,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    current_user.hashed_password = auth.get_password_hash(req.new_pin)
    db.commit()
    return {"msg": "PIN updated successfully"}

@app.post("/transactions/", response_model=schemas.TransactionResponse)
def create_transaction(
    request: Request,
    tx: schemas.TransactionCreate, 
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
            import json
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
                            timestamp=original_tx.timestamp
                        )
                raise HTTPException(status_code=409, detail="Transaction already processed")
    
    # 0. Verify PIN (outside lock - fail fast)
    if not auth.verify_password(tx.pin, current_user.hashed_password):
        raise HTTPException(status_code=401, detail="Incorrect PIN")

    # 1. Validate Receiver (outside lock - fail fast)
    receiver = db.query(models.User).filter(models.User.upi_id == tx.receiver_upi_id).first()
    if not receiver:
        # AUTO-REGISTER EXTERNAL USER
        # This allows payments to UPI IDs not yet in our system (Interop simulation)
        try:
             import random
             # Create dummy user for external UPI
             # Use timestamp to ensure uniqueness of "ext" mobile
             dummy_suffix = f"{int(datetime.utcnow().timestamp())}{random.randint(1000,9999)}"
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
                 hashed_password=auth.get_password_hash("external_default"),
                 balance=0.0
             )
             db.add(new_receiver)
             db.commit()
             db.refresh(new_receiver)
             
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
    risk_result = fraud_engine.evaluate_fraud(db, current_user, receiver, tx.amount)
    
    if risk_result == "HIGH":
        # Blocked by fraud engine - no need to attempt transfer
        new_tx = models.Transaction(
            transaction_id=f"TXN{datetime.utcnow().timestamp()}",
            sender_id=current_user.id,
            receiver_id=receiver.id,
            amount=tx.amount,
            encrypted_amount=security.encrypt_value(tx.amount),
            status="BLOCKED",
            risk_score=risk_result,
            timestamp=datetime.utcnow()
        )
        db.add(new_tx)
        db.commit()
        db.refresh(new_tx)
        return schemas.TransactionResponse(
            transaction_id=new_tx.transaction_id,
            sender_upi_id=current_user.upi_id,
            receiver_upi_id=receiver.upi_id,
            sender_name=current_user.username,
            receiver_name=receiver.username,
            amount=tx.amount,
            status="BLOCKED",
            risk_score=risk_result,
            timestamp=new_tx.timestamp,
            sender_mcc=current_user.mcc,
            receiver_mcc=receiver.mcc
        )

    # 3. Perform Transfer (ATOMIC TRANSACTION)
    # ═══════════════════════════════════════════════════════════════════════════
    # Unified Atomic Block: Handles Balance, History, Profiles, and Idempotency
    # ═══════════════════════════════════════════════════════════════════════════
    try:
        # PESSIMISTIC LOCKING (Postgres Compatible)
        # We must lock both users to prevent race conditions.
        # DEADLOCK PREVENTION: Always lock users in ID order (smaller ID first)
        
        first_id, second_id = sorted([current_user.id, receiver.id])
        
        # Lock first user
        u1 = db.query(models.User).with_for_update().filter(models.User.id == first_id).first()
        # Lock second user
        u2 = db.query(models.User).with_for_update().filter(models.User.id == second_id).first()
        
        if not u1 or not u2:
             raise HTTPException(status_code=404, detail="User not found during transaction lock")
             
        # Identify which is sender/receiver after locking
        sender_user = u1 if u1.id == current_user.id else u2
        receiver_user = u1 if u1.id == receiver.id else u2
        
        if sender_user.balance < tx.amount:
             raise HTTPException(status_code=400, detail="Insufficient balance")

        # B. UPDATE BALANCES
        sender_user.balance -= tx.amount
        receiver_user.balance += tx.amount

        # B2. UPDATE MERCHANT CATEGORY (if provided and valid)
        if tx.receiver_mcc and tx.receiver_mcc != '0000':
            # We trust the transaction source (QR code) more than default '0000'
            receiver_user.mcc = tx.receiver_mcc
        
        # C. CREATE TRANSACTION RECORD
        transaction_id = f"TXN{int(datetime.utcnow().timestamp()*1000)}"
        new_tx = models.Transaction(
            transaction_id=transaction_id,
            sender_id=sender_user.id,
            receiver_id=receiver_user.id,
            amount=tx.amount,
            encrypted_amount=security.encrypt_value(tx.amount),
            status="SUCCESS",
            risk_score=risk_result,
            timestamp=datetime.utcnow()
        )
        db.add(new_tx)

        # D. UPDATE PROFILES (Best Effort / Part of Transaction)
        if sender_user.sender_profile:
            sender_user.sender_profile.total_transactions_count += 1
            sender_user.sender_profile.total_transactions_amount += tx.amount
            sender_user.sender_profile.last_transaction_time = datetime.utcnow()
            if sender_user.sender_profile.total_transactions_count > 0:
                sender_user.sender_profile.avg_transaction_amount = (
                    sender_user.sender_profile.total_transactions_amount / 
                    sender_user.sender_profile.total_transactions_count
                )
        
        if receiver_user.receiver_profile:
            receiver_user.receiver_profile.total_received_count += 1
            receiver_user.receiver_profile.total_received_amount += tx.amount
            receiver_user.receiver_profile.last_received_time = datetime.utcnow()

        # E. IDEMPOTENCY KEY
        if tx.idempotency_key:
            import json
            response_obj = {
                "transaction_id": transaction_id,
                "sender_upi_id": sender_user.upi_id,
                "receiver_upi_id": receiver_user.upi_id,
                "sender_name": sender_user.username,
                "receiver_name": receiver_user.username,
                "amount": tx.amount,
                "status": "SUCCESS",
                "risk_score": risk_result,
                "timestamp": new_tx.timestamp.isoformat() 
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
        
        return schemas.TransactionResponse(
            transaction_id=new_tx.transaction_id,
            sender_upi_id=sender_user.upi_id,
            receiver_upi_id=receiver_user.upi_id,
            sender_name=sender_user.username,
            receiver_name=receiver_user.username,
            amount=new_tx.amount,
            status="SUCCESS",
            risk_score=risk_result,
            timestamp=new_tx.timestamp
        )

    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        print(f"Transaction Logic Error: {e}")
        import traceback
        traceback.print_exc()
        raise HTTPException(status_code=500, detail="Transaction failed due to system error")


# Simple In-Memory Cache for Home Data
# Key: user_id, Value: (timestamp, data)
HOME_DATA_CACHE = {}
CACHE_TTL = 5 # seconds

@app.get("/home-aggregate", response_model=schemas.HomeAggregateResponse)
def get_home_aggregate(
    current_user: models.User = Depends(get_current_user), 
    db: Session = Depends(get_db)
):
    # Check Cache
    if current_user.id in HOME_DATA_CACHE:
        ts, cached_data = HOME_DATA_CACHE[current_user.id]
        if (datetime.utcnow() - ts).total_seconds() < CACHE_TTL:
            return cached_data

    from sqlalchemy.orm import joinedload
    
    # 1. Get History (Limit 10) - Eager Load
    history_txs = db.query(models.Transaction).options(
        joinedload(models.Transaction.sender), 
        joinedload(models.Transaction.receiver)
    ).filter(
        (models.Transaction.sender_id == current_user.id) | 
        (models.Transaction.receiver_id == current_user.id)
    ).order_by(models.Transaction.timestamp.desc()).limit(10).all()
    
    history_list = []
    for t in history_txs:
        # Check manual mapping validity
        history_list.append(schemas.TransactionResponse(
            transaction_id=t.transaction_id,
            sender_upi_id=t.sender.upi_id,
            receiver_upi_id=t.receiver.upi_id,
            sender_name=t.sender.username,
            receiver_name=t.receiver.username,
            amount=t.amount,
            status=t.status,
            risk_score=t.risk_score,
            timestamp=t.timestamp,
            sender_mcc=t.sender.mcc,
            receiver_mcc=t.receiver.mcc
        ))

    # 2. Get Recent People (Limit 16)
    people_query = text("""
        SELECT u.id, u.username, u.mobile_encrypted, u.email_encrypted, u.upi_id, u.mcc, u.device_id_encrypted, u.balance, u.hashed_password
        FROM users u
        JOIN (
            SELECT 
                CASE WHEN sender_id = :uid THEN receiver_id ELSE sender_id END as other_id,
                MAX(timestamp) as last_tx
            FROM transactions 
            WHERE sender_id = :uid OR receiver_id = :uid
            GROUP BY other_id
        ) t ON u.id = t.other_id
        WHERE (u.mcc IS NULL OR u.mcc = '0000' OR u.mcc = '') AND u.id != :uid
        ORDER BY t.last_tx DESC
        LIMIT 16
    """)
    people_result = db.execute(people_query, {"uid": current_user.id}).fetchall()
    people_list = [
        models.User(
            id=row.id, username=row.username, mobile_encrypted=row.mobile_encrypted,
            email_encrypted=row.email_encrypted, upi_id=row.upi_id, mcc=row.mcc,
            device_id_encrypted=row.device_id_encrypted, balance=row.balance,
            hashed_password=row.hashed_password
        ) for row in people_result
    ]

    # 3. Get Recent Merchants (Limit 16)
    merchants_query = text("""
        SELECT u.id, u.username, u.mobile_encrypted, u.email_encrypted, u.upi_id, u.mcc, u.device_id_encrypted, u.balance, u.hashed_password
        FROM users u
        JOIN (
            SELECT 
                CASE WHEN sender_id = :uid THEN receiver_id ELSE sender_id END as other_id,
                MAX(timestamp) as last_tx
            FROM transactions 
            WHERE sender_id = :uid OR receiver_id = :uid
            GROUP BY other_id
        ) t ON u.id = t.other_id
        WHERE u.mcc IS NOT NULL AND u.mcc != '0000' AND u.mcc != '' AND u.id != :uid
        ORDER BY t.last_tx DESC
        LIMIT 16
    """)
    merchants_result = db.execute(merchants_query, {"uid": current_user.id}).fetchall()
    merchants_list = [
        models.User(
            id=row.id, username=row.username, mobile_encrypted=row.mobile_encrypted,
            email_encrypted=row.email_encrypted, upi_id=row.upi_id, mcc=row.mcc,
            device_id_encrypted=row.device_id_encrypted, balance=row.balance,
            hashed_password=row.hashed_password
        ) for row in merchants_result
    ]

    response_data = schemas.HomeAggregateResponse(
        user=current_user,
        history=history_list,
        people=people_list,
        merchants=merchants_list
    )
    
    # Update Cache
    HOME_DATA_CACHE[current_user.id] = (datetime.utcnow(), response_data)
    
    return response_data

@app.get("/transactions/history", response_model=list[schemas.TransactionResponse])
def read_history(current_user: models.User = Depends(get_current_user), db: Session = Depends(get_db)):
    # Check Cache
    CACHE_KEY = f"history_{current_user.id}"
    if CACHE_KEY in HOME_DATA_CACHE:
        ts, cached_data = HOME_DATA_CACHE[CACHE_KEY]
        if (datetime.utcnow() - ts).total_seconds() < CACHE_TTL:
            return cached_data

    from sqlalchemy.orm import joinedload
    # Get sent and received
    # OPTIMIZATION: Eager load sender and receiver to prevent N+1 queries
    txs = db.query(models.Transaction).options(
        joinedload(models.Transaction.sender), 
        joinedload(models.Transaction.receiver)
    ).filter(
        (models.Transaction.sender_id == current_user.id) | 
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
            amount=t.amount,
            status=t.status,
            risk_score=t.risk_score,
            timestamp=t.timestamp,
            sender_mcc=t.sender.mcc,
            receiver_mcc=t.receiver.mcc
        ))
        
    # Update Cache
    HOME_DATA_CACHE[CACHE_KEY] = (datetime.utcnow(), results)
        
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
        if (datetime.utcnow() - ts).total_seconds() < CACHE_TTL:
            return cached_data

    # FAST SQL QUERY
    # PEOPLE = MCC is NULL OR MCC is '0000' OR MCC is empty ''
    
    query = text("""
        SELECT u.id, u.username, u.mobile_encrypted, u.email_encrypted, u.upi_id, u.mcc, u.device_id_encrypted, u.balance, u.hashed_password
        FROM users u
        JOIN (
            SELECT 
                CASE WHEN sender_id = :uid THEN receiver_id ELSE sender_id END as other_id,
                MAX(timestamp) as last_tx
            FROM transactions 
            WHERE sender_id = :uid OR receiver_id = :uid
            GROUP BY other_id
        ) t ON u.id = t.other_id
        WHERE (u.mcc IS NULL OR u.mcc = '0000' OR u.mcc = '') AND u.id != :uid
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
            device_id_encrypted=row.device_id_encrypted,
            balance=row.balance,
            hashed_password=row.hashed_password
        ))
        
    # Update Cache
    HOME_DATA_CACHE[CACHE_KEY] = (datetime.utcnow(), users)
        
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
        if (datetime.utcnow() - ts).total_seconds() < CACHE_TTL:
            return cached_data

    # FAST SQL QUERY
    # MERCHANTS = MCC is NOT NULL AND MCC != '0000' AND MCC != ''
    query = text("""
        SELECT u.id, u.username, u.mobile_encrypted, u.email_encrypted, u.upi_id, u.mcc, u.device_id_encrypted, u.balance, u.hashed_password
        FROM users u
        JOIN (
            SELECT 
                CASE WHEN sender_id = :uid THEN receiver_id ELSE sender_id END as other_id,
                MAX(timestamp) as last_tx
            FROM transactions 
            WHERE sender_id = :uid OR receiver_id = :uid
            GROUP BY other_id
        ) t ON u.id = t.other_id
        WHERE u.mcc IS NOT NULL AND u.mcc != '0000' AND u.mcc != '' AND u.id != :uid
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
            device_id_encrypted=row.device_id_encrypted,
            balance=row.balance,
            hashed_password=row.hashed_password
        ))
        
    # Update Cache
    HOME_DATA_CACHE[CACHE_KEY] = (datetime.utcnow(), users)
        
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
        timestamp=datetime.utcnow()
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

    # 1. Fetch Transactions
    txs = db.query(models.Transaction).filter(
        (
            (models.Transaction.sender_id == current_user.id) & 
            (models.Transaction.receiver_id == target_user.id)
        ) | 
        (
            (models.Transaction.sender_id == target_user.id) & 
            (models.Transaction.receiver_id == current_user.id)
        )
    ).order_by(models.Transaction.timestamp.desc()).limit(50).all()
    
    # 2. Fetch Messages
    msgs = db.query(models.Message).filter(
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
    # Filter visibility logic: Only show if SUCCESS or (FAILED and I am SENDER)
    for t in txs:
        should_show = False
        if t.status == "SUCCESS":
            should_show = True
        elif t.sender_id == current_user.id:
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
                "receiver_mcc": t.receiver.mcc
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
        
    # Sort combined list by timestamp DESC (Newest first)
    combined.sort(key=lambda x: x['timestamp'], reverse=True)
        
    return combined
