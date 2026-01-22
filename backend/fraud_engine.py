import models
from sqlalchemy.orm import Session
from datetime import datetime, timedelta

# Fraud Logic Constants
RISK_THRESHOLD_HIGH = 70
RISK_THRESHOLD_WARN = 40

def evaluate_fraud(db: Session, sender: models.User, receiver: models.User, amount: float):
    """
    Evaluates fraud risk based on:
    0.6 * Sender Risk + 0.4 * Receiver Risk
    
    Returns: (Risk Score (0-100), Risk Label (SAFE, WARN, HIGH))
    """
    sender_risk = _calculate_sender_risk(sender, amount)
    receiver_risk = _calculate_receiver_risk(receiver, amount)
    
    final_score = (0.6 * sender_risk) + (0.4 * receiver_risk)
    
    if final_score >= RISK_THRESHOLD_HIGH:
        return "HIGH"
    elif final_score >= RISK_THRESHOLD_WARN:
        return "WARN"
    else:
        return "SAFE"

def _calculate_sender_risk(user: models.User, amount: float) -> float:
    risk = 0
    profile = user.sender_profile
    if not profile:
        return 0  # No history, start neutral or low risk? Let's say 0 for new user
    
    # Rule 1: Amount far above average (e.g., > 3x average)
    if profile.total_transactions_count > 5:
        if amount > (profile.avg_transaction_amount * 3):
            risk += 50
        elif amount > (profile.avg_transaction_amount * 2):
            risk += 30

    # Rule 2: Late night transactions (12 AM - 5 AM)
    current_hour = datetime.utcnow().hour
    if 0 <= current_hour <= 5:
        risk += 20
        
    # Rule 3: High frequency (simplified check)
    # Ideally we check recent txs, but for now relying on aggregated profile isn't enough for frequency 
    # unless we store 'last_transaction_time' and check gap.
    if profile.last_transaction_time:
        time_diff = datetime.utcnow() - profile.last_transaction_time
        if time_diff.total_seconds() < 60: # Transactions within 1 minute
            risk += 40

    return min(risk, 100)

def _calculate_receiver_risk(user: models.User, amount: float) -> float:
    risk = 0
    profile = user.receiver_profile
    if not profile:
        return 0
        
    # Rule 1: Sudden spike in incoming amount (simplified)
    # If this single transaction is huge compared to history
    if profile.total_received_count > 5:
        avg_received = profile.total_received_amount / profile.total_received_count
        if amount > (avg_received * 5):
            risk += 60
            
    # Rule 2: New account receiving money? (Low transaction count)
    if profile.total_received_count < 3 and amount > 5000:
        risk += 30

    return min(risk, 100)
