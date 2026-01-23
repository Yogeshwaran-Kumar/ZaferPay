from fastapi import FastAPI, Depends, HTTPException, status, Header
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
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
                # Return detailed error for better UX
                raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail={
                        "message": "already_logged_in",
                        "info": "You are currently logged in on another device. To continue on this device, you must logout from the other device."
                    },
                )
            # Force logout from other device - update device_id
            print(f"Force logout: User {user.username} logging out from device {user.device_id} and logging into {x_device_id}")
        
        # Update device_id (either first login or force logout)
        user.device_id = x_device_id
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
    has_device_conflict = False
    if x_device_id and user.device_id and user.device_id != x_device_id:
        # User is logged in on a different device
        has_device_conflict = True
        print(f"Device conflict detected for user {user.username}: DB device={user.device_id}, Request device={x_device_id}")
    
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
    # Clear device_id to allow login from another device
    device_id = current_user.device_id
    current_user.device_id = None
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
    user = db.query(models.User).filter(models.User.upi_id == upi_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="UPI ID not found")
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
            amount=t.amount,
            status=t.status,
            risk_score=t.risk_score,
            timestamp=t.timestamp
        ))
    return results
