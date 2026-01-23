from sqlalchemy.orm import Session
import models, auth

def seed_data(db: Session):
    # Check if data exists
    if db.query(models.User).first():
        return

    print("Seeding mock data...")
    
    # Create Users
    # SECURITY UPDATE: Hardcoded users removed. 
    # Use /auth/register endpoint to create users.
    users = [] 

    for u in users:
        hashed = None
        if "password" in u:
            hashed = auth.get_password_hash(u["password"])
            
        db_user = models.User(
            username=u["username"],
            mobile_number=u["mobile"],
            email=u["email"],
            hashed_password=hashed,
            upi_id=u["upi"],
            balance=u["balance"]
        )
        db.add(db_user)
        db.flush() # flush to get id
        
        # Create Profiles
        s_prof = models.SenderProfile(user_id=db_user.id, avg_transaction_amount=500.0, total_transactions_count=5)
        r_prof = models.ReceiverProfile(user_id=db_user.id)
        
        db.add(s_prof)
        db.add(r_prof)
        
    db.commit()
    print("Seeding complete.")
