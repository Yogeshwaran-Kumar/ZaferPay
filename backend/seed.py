from sqlalchemy.orm import Session
import models, auth

def seed_data(db: Session):
    # Check if data exists
    if db.query(models.User).first():
        return

    print("Seeding mock data...")
    
    # Create Users
    users = [
        {"username": "userA", "email": "usera@example.com", "password": "password123", "upi": "userA@mockbank", "balance": 50000.0},
        {"username": "userB", "email": "userb@example.com", "password": "password123", "upi": "userB@mockbank", "balance": 25000.0},
        {"username": "shopC", "email": "shopc@example.com", "password": "password123", "upi": "shopC@mockbank", "balance": 10000.0},
        {"username": "trustD", "email": "trustd@example.com", "password": "password123", "upi": "trustD@mockbank", "balance": 500000.0},
    ]

    for u in users:
        db_user = models.User(
            username=u["username"],
            email=u["email"],
            hashed_password=auth.get_password_hash(u["password"]),
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
