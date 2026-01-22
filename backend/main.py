from fastapi import FastAPI, Depends, HTTPException, status
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
    return user

@app.post("/token", response_model=schemas.Token)
async def login_for_access_token(form_data: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.username == form_data.username).first()
    if not user or not auth.verify_password(form_data.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    access_token_expires = timedelta(minutes=auth.ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = auth.create_access_token(
        data={"sub": user.username}, expires_delta=access_token_expires
    )
    return {"access_token": access_token, "token_type": "bearer"}

@app.get("/users/me", response_model=schemas.UserResponse)
async def read_users_me(current_user: models.User = Depends(get_current_user)):
    return current_user

@app.post("/transactions/", response_model=schemas.TransactionResponse)
async def create_transaction(
    tx: schemas.TransactionCreate, 
    current_user: models.User = Depends(get_current_user), 
    db: Session = Depends(get_db)
):
    # 1. Validate Receiver
    receiver = db.query(models.User).filter(models.User.upi_id == tx.receiver_upi_id).first()
    if not receiver:
        raise HTTPException(status_code=404, detail="Receiver UPI ID not found")
    
    if receiver.id == current_user.id:
        raise HTTPException(status_code=400, detail="Cannot send money to self")

    # 2. Check Balance
    if current_user.balance < tx.amount:
        raise HTTPException(status_code=400, detail="Insufficient balance")

    # 3. Fraud Check
    risk_result = fraud_engine.evaluate_fraud(db, current_user, receiver, tx.amount)
    
    # 4. Process Status (For this mock, HIGH risk blocked?)
    # Requirement says "Risk result returned... User proceeds or cancels". 
    # But for API, let's say "BLOCKED" if user forces it? 
    # Actually, usually the API returns the check first OR we just process it.
    # Let's assume this endpoint EXECUTES the transaction.
    # If Risk is HIGH, maybe we block it automatically?
    # "Backend evaluates... Risk result returned... User proceeds" -> implies 2-step flow or 1-step with confirmation.
    # To keep it simple: 
    # If WARN/HIGH, we mark it but might still allow or we can reject. 
    # Let's BLOCK on HIGH for safety demonstration.
    
    tx_status = "SUCCESS"
    if risk_result == "HIGH":
        tx_status = "BLOCKED"
        # Don't deduct money
    elif risk_result == "WARN":
        tx_status = "SUCCESS" # Allow with warning logged
    
    # 5. Execute Transfer if SUCCESS
    if tx_status == "SUCCESS":
        current_user.balance -= tx.amount
        receiver.balance += tx.amount
        
        # Update Profiles (Simplified)
        s_prof = current_user.sender_profile
        s_prof.total_transactions_count += 1
        s_prof.monthly_volume += tx.amount
        # Re-calculate average
        # (New Total / New Count) approximately
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
async def read_history(current_user: models.User = Depends(get_current_user), db: Session = Depends(get_db)):
    # Get sent and received
    txs = db.query(models.Transaction).filter(
        (models.Transaction.sender_id == current_user.id) | 
        (models.Transaction.receiver_id == current_user.id)
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
