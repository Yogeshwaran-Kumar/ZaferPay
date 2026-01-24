from fastapi import FastAPI, Depends, HTTPException, status, Header
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from sqlalchemy import text
from datetime import timedelta, datetime
import models, schemas, auth, database, fraud_engine
import seed

app = FastAPI(title="Application-2 Mock Bank")

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

# Run Seed on Startup (Simple toggle)
# In production, this would be a separate script, but for "works immediately", we check on start
try:
    with database.SessionLocal() as db:
        seed.seed_data(db)
except Exception as e:
    print(f"Seeding skipped or failed: {e}")

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

def get_db():
    db = database.SessionLocal()
    try:
        yield db
    finally:
        db.close()

async def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)):
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
    if user.device_id and token_device_id != user.device_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Logged in on another device",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    # Update last_active_at on every authenticated request
    user.last_active_at = datetime.utcnow()
    db.commit()
        
    return user

@app.post("/token", response_model=schemas.Token)
def login_for_access_token(
    form_data: OAuth2PasswordRequestForm = Depends(), 
    db: Session = Depends(get_db),
    x_device_id: str = Header(None),
    force_logout: bool = False
):
    # Authenticate by Mobile Number OR Email (passed in form_data.username)
    identifier = form_data.username
    user = db.query(models.User).filter(
        (models.User.mobile_number == identifier) | 
        (models.User.email == identifier)
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
        if user.device_id and user.device_id != x_device_id:
            if not force_logout:
                # User is already logged in on another device
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail={
                        "message": "already_logged_in",
                        "info": "You are currently logged in on another device. To continue on this device, you must logout from the other device."
                    },
                )
            # Force logout from other device - update device_id
            print(f"Force logout: User {user.username} logging out from {user.device_id} and logging into {x_device_id}")
        
        # Update device_id (either first login or force logout)
        user.device_id = x_device_id
        user.last_active_at = datetime.utcnow()  # Mark as active now
        db.commit()
    
    access_token_expires = timedelta(minutes=auth.ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = auth.create_access_token(
        data={"sub": user.username, "device_id": x_device_id}, expires_delta=access_token_expires
    )
    return {"access_token": access_token, "token_type": "bearer"}

@app.post("/auth/check-mobile", response_model=schemas.MobileCheckResponse)
def check_mobile(
    check: schemas.MobileCheckRequest,
    db: Session = Depends(get_db),
    x_device_id: str = Header(None)
):
    # Search by mobile number OR email
    identifier = check.mobile_number # We reuse this field name from frontend but it can be email
    print(f"DEBUG: Checking mobile/email for identifier: '{identifier}'")
    
    user = db.query(models.User).filter(
        (models.User.mobile_number == identifier) | 
        (models.User.email == identifier)
    ).first()
    
    if not user:
        # Check username just in case
        user = db.query(models.User).filter(models.User.username == identifier).first()
    
    if not user:
        # User not found -> treat as NEW user (Registration Flow)
        # However, for import scenario, we expect them to exist. 
        # If not existing, frontend handles 'new' status
        return {
            "exists": False, 
            "status": "new",
            "upi_id": None,
            "has_device_conflict": False
        }
    
    # Check if PIN is set
    # We assume empty password hash or specifically "NULL" string means not set
    if not user.hashed_password or user.hashed_password == "NULL":
        return {
            "exists": True, 
            "status": "new", # User exists but needs PIN set (unlikely for imported data with PINs)
            "upi_id": user.upi_id,
            "has_device_conflict": False
        }
    
    # Existing user with PIN - Check for device conflict
    # Show conflict if a different device is currently logged in (device_id exists and differs)
    has_device_conflict = False
    if x_device_id and user.device_id and user.device_id != x_device_id:
        has_device_conflict = True
        print(f"Device conflict: {user.username} logged in on {user.device_id}, request from {x_device_id}")
    
    return {
        "exists": True, 
        "status": "existing",
        "upi_id": user.upi_id,
        "has_device_conflict": has_device_conflict
    }

@app.post("/auth/register", response_model=schemas.UserResponse)
def register_user(
    user: schemas.UserRegister,
    db: Session = Depends(get_db)
):
    # Check if user exists
    db_user = db.query(models.User).filter(
        (models.User.username == user.username) | 
        (models.User.mobile_number == user.mobile_number)
    ).first()
    if db_user:
        raise HTTPException(status_code=400, detail="Username or Mobile already registered")
    
    # Generate default UPI ID if not provided
    # Fallback to username instead of specific suffix
    new_upi = user.username
    
    new_user = models.User(
        username=user.username,
        mobile_number=user.mobile_number,
        email=user.email,
        upi_id=new_upi,
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
def set_pin(
    req: schemas.PinSetRequest,
    db: Session = Depends(get_db)
):
    user = db.query(models.User).filter(models.User.mobile_number == req.mobile_number).first()
    if not user:
        # Check by username just in case
        user = db.query(models.User).filter(models.User.username == req.mobile_number).first()
        
    if not user:
        # NEW USER REGISTRATION via Set PIN
        # Create a new user since they passed the mobile check and set a PIN
        print(f"Creating new user for mobile: {req.mobile_number}")
        
        # Generate defaults
        username = f"User{req.mobile_number}"
        # Use provided UPI ID or fallback to mobile_number
        upi_id = req.upi_id if req.upi_id else req.mobile_number
        
        new_user = models.User(
            username=username,
            mobile_number=req.mobile_number,
            email=f"{req.mobile_number}@example.com", # Placeholder
            upi_id=upi_id,
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
    device_id = current_user.device_id
    current_user.device_id = None
    current_user.last_active_at = None
    db.commit()
    print(f"User {current_user.username} logged out from device {device_id}")
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
        print(f"DEBUG: Auto-Creating user for UPI: {upi_id}")
        
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

@app.get("/users/lookup-phone/{phone_number}", response_model=schemas.UserLookupResponse)
def lookup_user_by_phone(phone_number: str, current_user: models.User = Depends(get_current_user), db: Session = Depends(get_db)):
    # Normalize phone number - remove all non-digit characters
    normalized_phone = ''.join(filter(str.isdigit, phone_number))
    
    # Try to find by mobile_number field
    user = db.query(models.User).filter(models.User.mobile_number == normalized_phone).first()
    
    # Optimized: SEARCH STRATEGY CHANGED
    # We remove the leading wildcard search (LIKE %...) because it causes full table scans.
    # Instead, we rely on exact matches or simple variations.
    
    if not user:
        # If the user typed 1234567890, but we store +911234567890, let's try adding country code.
        # This is O(log N) because it hits the index directly.
        if len(normalized_phone) == 10:
             user = db.query(models.User).filter(models.User.mobile_number == f"91{normalized_phone}").first()
             if not user:
                 user = db.query(models.User).filter(models.User.mobile_number == f"+91{normalized_phone}").first()

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
    tx: schemas.TransactionCreate, 
    current_user: models.User = Depends(get_current_user), 
    db: Session = Depends(get_db)
):
    # 0. Verify PIN
    if not auth.verify_password(tx.pin, current_user.hashed_password):
        raise HTTPException(status_code=401, detail="Incorrect PIN")

    # 1. Validate Receiver
    receiver = db.query(models.User).filter(models.User.upi_id == tx.receiver_upi_id).first()
    if not receiver:
        raise HTTPException(status_code=404, detail="Receiver UPI ID not found")
    
    if receiver.id == current_user.id:
        raise HTTPException(status_code=400, detail="Cannot send money to self")

    # 2. Check Balance & 3. Fraud Check
    # We evaluate fraud regardless, but balance check determines immediate failure
    
    tx_status = "SUCCESS"
    risk_result = fraud_engine.evaluate_fraud(db, current_user, receiver, tx.amount)
    
    if current_user.balance < tx.amount:
        tx_status = "FAILED"
        # We can use a special indicator for risk or just rely on status
        # Let's append to risk_result or use a standard code if compatible
        # For simplicity, we just save status=FAILED
    elif risk_result == "HIGH":
        tx_status = "BLOCKED"
    elif risk_result == "WARN":
        tx_status = "SUCCESS" 
    
    # 5. Execute Transfer if SUCCESS
    if tx_status == "SUCCESS":
        current_user.balance -= tx.amount
        receiver.balance += tx.amount
        
        # Update Profiles (Simplified)
        s_prof = current_user.sender_profile
        s_prof.total_transactions_count += 1
        s_prof.monthly_volume += tx.amount
        # Re-calculate average
        s_prof.avg_transaction_amount = ( (s_prof.avg_transaction_amount * (s_prof.total_transactions_count-1)) + tx.amount ) / s_prof.total_transactions_count
        s_prof.last_transaction_time = datetime.utcnow()
        
        r_prof = receiver.receiver_profile
        r_prof.total_received_count += 1
        r_prof.total_received_amount += tx.amount

    # 6. Record Transaction
    new_tx = models.Transaction(
        transaction_id=f"TXN{datetime.utcnow().timestamp()}",
        sender_id=current_user.id,
        receiver_id=receiver.id,
        amount=tx.amount,
        status=tx_status,
        risk_score=risk_result,
        timestamp=datetime.utcnow()
    )
    db.add(new_tx)
    db.commit()
    db.refresh(new_tx)
    
    # Return response (include UPI IDs manually since model relation might need load)
    return schemas.TransactionResponse(
        transaction_id=new_tx.transaction_id,
        sender_upi_id=current_user.upi_id,
        receiver_upi_id=receiver.upi_id,
        sender_name=current_user.username,
        receiver_name=receiver.username,
        amount=new_tx.amount,
        status=new_tx.status,
        risk_score=new_tx.risk_score,
        timestamp=new_tx.timestamp
    )

@app.get("/transactions/history", response_model=list[schemas.TransactionResponse])
def read_history(current_user: models.User = Depends(get_current_user), db: Session = Depends(get_db)):
    # Get sent and received
    txs = db.query(models.Transaction).filter(
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
            timestamp=t.timestamp
        ))
    return results

@app.get("/transactions/recent-people", response_model=list[schemas.UserResponse])
def get_recent_people(
    limit: int = 16,
    current_user: models.User = Depends(get_current_user), 
    db: Session = Depends(get_db)
):
    # FAST SQL QUERY
    # We use raw SQL to efficiently find distinct counterparties sorted by most recent transaction.
    # This avoids fetching all history into Python memory.
    
    query = text("""
        SELECT u.id, u.username, u.mobile_number, u.email, u.upi_id, u.mcc, u.device_id, u.balance, u.hashed_password
        FROM users u
        JOIN (
            SELECT 
                CASE WHEN sender_id = :uid THEN receiver_id ELSE sender_id END as other_id,
                MAX(timestamp) as last_tx
            FROM transactions 
            WHERE sender_id = :uid OR receiver_id = :uid
            GROUP BY other_id
        ) t ON u.id = t.other_id
        WHERE u.mcc IS NULL AND u.id != :uid
        ORDER BY t.last_tx DESC
        LIMIT :limit
    """)
    
    result = db.execute(query, {"uid": current_user.id, "limit": limit}).fetchall()
    
    # Map raw results back to Pydantic models (or dicts suitable for response)
    # Since we selected columns matching the User model, we can reconstruct them.
    users = []
    for row in result:
        # row is a Row object (tuple-like)
        # We need to match the UserResponse schema
        users.append(models.User(
            id=row.id,
            username=row.username,
            mobile_number=row.mobile_number,
            email=row.email,
            upi_id=row.upi_id,
            mcc=row.mcc,
            device_id=row.device_id,
            balance=row.balance,
            hashed_password=row.hashed_password # Needed for internal logic, though response model filters it
        ))
        
    return users

@app.get("/transactions/recent-merchants", response_model=list[schemas.UserResponse])
def get_recent_merchants(
    limit: int = 16,
    current_user: models.User = Depends(get_current_user), 
    db: Session = Depends(get_db)
):
    # FAST SQL QUERY
    query = text("""
        SELECT u.id, u.username, u.mobile_number, u.email, u.upi_id, u.mcc, u.device_id, u.balance, u.hashed_password
        FROM users u
        JOIN (
            SELECT 
                CASE WHEN sender_id = :uid THEN receiver_id ELSE sender_id END as other_id,
                MAX(timestamp) as last_tx
            FROM transactions 
            WHERE sender_id = :uid OR receiver_id = :uid
            GROUP BY other_id
        ) t ON u.id = t.other_id
        WHERE u.mcc IS NOT NULL AND u.id != :uid
        ORDER BY t.last_tx DESC
        LIMIT :limit
    """)
    
    result = db.execute(query, {"uid": current_user.id, "limit": limit}).fetchall()
    
    users = []
    for row in result:
        users.append(models.User(
            id=row.id,
            username=row.username,
            mobile_number=row.mobile_number,
            email=row.email,
            upi_id=row.upi_id,
            mcc=row.mcc,
            device_id=row.device_id,
            balance=row.balance,
            hashed_password=row.hashed_password
        ))
        
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
        content=msg.content,
        timestamp=datetime.utcnow()
    )
    db.add(new_msg)
    db.commit()
    db.refresh(new_msg)
    
    return schemas.MessageResponse(
        id=new_msg.id,
        sender_upi_id=current_user.upi_id,
        receiver_upi_id=receiver.upi_id,
        content=new_msg.content,
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
                "timestamp": t.timestamp
            })
            
    # Process Messages
    for m in msgs:
        combined.append({
            "type": "message",
            "id": m.id,
            "sender_upi_id": m.sender.upi_id,
            "receiver_upi_id": m.receiver.upi_id,
            "content": m.content,
            "timestamp": m.timestamp
        })
        
    # Sort combined list by timestamp DESC (Newest first)
    combined.sort(key=lambda x: x['timestamp'], reverse=True)
        
    return combined
