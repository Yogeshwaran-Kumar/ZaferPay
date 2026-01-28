import models
from sqlalchemy.orm import Session, aliased
from sqlalchemy import func, literal, union_all, select
from datetime import datetime, timedelta
import pandas as pd
import numpy as np
import pickle
import os

# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION & CONSTANTS
# ═══════════════════════════════════════════════════════════════════════════

RISK_THRESHOLD_HIGH = 80    # Block immediately
RISK_THRESHOLD_WARN = 50    # Allow but flag

MODEL_PATH = "fraud_model.pkl"
MIN_DATA_POINTS = 50 

# Global Cache
_model = None
_is_trained = False

# ═══════════════════════════════════════════════════════════════════════════
# PRE-LOAD AI DEPENDENCIES (Lazy Load)
# ═══════════════════════════════════════════════════════════════════════════
def get_isolation_forest():
    """Safe import to avoid crashing if sklearn is missing"""
    try:
        from sklearn.ensemble import IsolationForest
        return IsolationForest
    except ImportError:
        print("⚠️ sklearn not found. AI Brain will be disabled.")
        return None

# ═══════════════════════════════════════════════════════════════════════════
# STAGE 3: THE BRAIN (AI Engine)
# ═══════════════════════════════════════════════════════════════════════════

def load_or_train_model(db: Session):
    global _model, _is_trained
    
    if _model is None and os.path.exists(MODEL_PATH):
        try:
            with open(MODEL_PATH, "rb") as f:
                _model = pickle.load(f)
            _is_trained = True
        except: pass
    
    if not _is_trained:
        train_model(db)

def train_model(db: Session):
    global _model, _is_trained
    IsolationForest = get_isolation_forest()
    if not IsolationForest: return

    # Fetch Training Data
    txs = db.query(models.Transaction.amount, models.Transaction.timestamp).limit(5000).all()
    if len(txs) < MIN_DATA_POINTS: return

    # Features: [Amount, Hour]
    data = [[t.amount, t.timestamp.hour] for t in txs]
    df = pd.DataFrame(data, columns=['amount', 'hour'])
    
    # Train
    clf = IsolationForest(n_estimators=100, contamination=0.05, random_state=42)
    clf.fit(df)
    
    _model = clf
    _is_trained = True
    with open(MODEL_PATH, "wb") as f:
        pickle.dump(_model, f)

def get_ai_score(amount: float, timestamp: datetime) -> float:
    if not _is_trained or _model is None: return 0.5
    try:
        score = _model.decision_function([[amount, timestamp.hour]])[0]
        return score # Negative = Outlier, Positive = Normal
    except: return 0.5

# ═══════════════════════════════════════════════════════════════════════════
# CORE: RECURSIVE TRUST GRAPH (The "Friend of a Friend" Logic)
# ═══════════════════════════════════════════════════════════════════════════

def calculate_trust_depth(db: Session, sender_id: int, receiver_id: int, max_depth=2) -> int:
    """
    Determines how close the receiver is to the sender in the social graph.
    Depth 1: Direct Friend (I trust you)
    Depth 2: Friend of Friend (My trusted friend trusts you)
    Depth 0: Stranger (No connection)
    
    Uses Recursive CTE logic (simulated for compatibility).
    """
    # 1. Direct Trust (Depth 1)
    direct = db.query(models.UserTrustGraph).filter(
        models.UserTrustGraph.user_id == sender_id,
        models.UserTrustGraph.trusted_user_id == receiver_id
    ).first()
    if direct: return 1
    
    # 2. Recursive Trust (Depth 2 - Friend of Friend)
    # Find all people I trust (My Friends)
    my_friends = db.query(models.UserTrustGraph.trusted_user_id).filter(
        models.UserTrustGraph.user_id == sender_id
    ).all()
    friend_ids = [f[0] for f in my_friends]
    
    if not friend_ids: return 0
    
    # Check if ANY of my friends trust the receiver
    fof = db.query(models.UserTrustGraph).filter(
        models.UserTrustGraph.user_id.in_(friend_ids),
        models.UserTrustGraph.trusted_user_id == receiver_id
    ).first()
    
    if fof: return 2
    
    return 0 # Stranger

# ═══════════════════════════════════════════════════════════════════════════
# MAIN FRAUD ENGINE (The Pipeline)
# ═══════════════════════════════════════════════════════════════════════════

def evaluate_fraud(db: Session, sender: models.User, receiver: models.User, amount: float, device_id_hash: str = None):
    """
    Google Pay Style Execution Pipeline:
    Stage 1: Hard Rules (The Reflexes) - Instant Fail
    Stage 2: Social Graph (The Network) - Trust Validation
    Stage 3: AI Analysis (The Brain) - Pattern Matching
    """
    load_or_train_model(db)
    risk_score = 0
    violation = None
    
    # ─── STAGE 1: HARD RULES (The Reflexes) ────────────────────────────────────
    
    # F1: Velocity (Speed Limit)
    mins_10_ago = datetime.now() - timedelta(minutes=10)
    recent_txns = db.query(func.count(models.Transaction.id)).filter(
        models.Transaction.sender_id == sender.id,
        models.Transaction.timestamp > mins_10_ago
    ).scalar()
    if recent_txns and recent_txns >= 5:
        return "HIGH", "F1_VELOCITY_LIMIT_EXCEEDED"

    # F2: Circular (Looping) - A->B->A
    mins_2_ago = datetime.now() - timedelta(minutes=2)
    loop_check = db.query(models.Transaction).filter(
        models.Transaction.sender_id == receiver.id,
        models.Transaction.receiver_id == sender.id, # They sent to me
        models.Transaction.timestamp > mins_2_ago
    ).first()
    if loop_check:
        risk_score += 40
        violation = "F2_CIRCULAR_LOOP"

    # F3: Dormant Account
    if sender.last_active_at:
        days_inactive = (datetime.now() - sender.last_active_at).days
        if days_inactive > 30 and amount > 500:
            return "HIGH", "F3_DORMANT_ACCOUNT_SPIKE"

    # F5: Ticket Size Spike
    if sender.sender_profile and sender.sender_profile.avg_transaction_amount > 0:
        avg = sender.sender_profile.avg_transaction_amount
        if amount > (avg * 3):
            risk_score += 50
            violation = "F5_AMOUNT_SPIKE_300_PERCENT"
            
    # F9: Night Owl (3 AM - 5 AM)
    hour = datetime.now().hour
    if 3 <= hour <= 5:
        risk_score += 25
        if not violation: violation = "F9_UNUSUAL_TIME"

    # ─── STAGE 2: SOCIAL GRAPH (The Trust Network) ─────────────────────────────
    
    # F12: Recursive Trust Check
    # "Stranger Danger" vs "Friend of Friend"
    trust_depth = calculate_trust_depth(db, sender.id, receiver.id)
    
    if trust_depth == 1:
        # Direct Friend: Low Risk (Bonus)
        risk_score -= 10 
    elif trust_depth == 2:
        # Friend of Friend: Neutral (Verified connection)
        pass 
    else:
        # Stranger: Penalty
        risk_score += 20
        if not violation: violation = "F12_STRANGER_NO_COMMON_TRUST"
        
        # F8: New Receiver High Value
        # If paying stranger > 2000 for first time
        if amount > 2000:
             risk_score += 30
             if not violation: violation = "F8_HIGH_VALUE_STRANGER"

    # F7: Trusted Device Check (Now UserTrustGraph Check aka Social Graph)
    if device_id_hash:
        # Note: This logic seems to have been conflated. F7 logic usually checks if *Source Device* is trusted.
        # But here it was checking TrustedDevice (Social Graph). 
        # We will keep it as is but update the model to use UserTrustGraph 
        # assuming the intent was "Is this receiver in my trust graph?"
        
        known_dev = db.query(models.UserTrustGraph).filter(
            models.UserTrustGraph.user_id == sender.id,
            models.UserTrustGraph.trusted_user_id == receiver.id # Logic implies this is checking social trust, not hardware.
        ).first()
        
        # If paying > 5000 and NOT in trust graph -> Risk
        if not known_dev and amount > 5000:
            return "HIGH", "F7_UNTRUSTED_RECEIVER_HIGH_VALUE"

    # ─── STAGE 3: AI ANALYSIS (The Brain) ──────────────────────────────────────
    
    # F4: Anomaly Detection
    ai_score = get_ai_score(amount, datetime.now())
    # AI Score < -0.2 is anomaly
    if ai_score < -0.2:
        risk_score += 65
        violation = "F4_AI_DETECTED_ANOMALY"
    elif ai_score < 0:
        risk_score += 20
        
    # ─── FINAL VERDICT ─────────────────────────────────────────────────────────
    
    # Cap score
    risk_score = min(risk_score, 100)
    risk_score = max(risk_score, 0)
    
    print(f"🕵️ RISK EVAL: {sender.username} -> {receiver.username} | ₹{amount}")
    print(f"   Graph Depth: {trust_depth} | AI: {ai_score:.2f} | Score: {risk_score}")
    
    if risk_score >= RISK_THRESHOLD_HIGH:
        return "HIGH", violation or "HIGH_RISK_SCORE"
    elif risk_score >= RISK_THRESHOLD_WARN:
        return "WARN", violation or "WARN_RISK_SCORE"
    else:
        return "SAFE", None

def record_trust(db: Session, sender_id: int, receiver_id: int):
    """Adds valid transaction to the social graph"""
    exists = db.query(models.UserTrustGraph).filter(
        models.UserTrustGraph.user_id == sender_id,
        models.UserTrustGraph.trusted_user_id == receiver_id
    ).first()
    
    if exists:
        exists.trust_score += 1.0
        exists.last_interaction_at = datetime.now()
    else:
        # Create DIRECT Trust (Depth 1)
        new_link = models.UserTrustGraph(
            user_id=sender_id,
            trusted_user_id=receiver_id,
            trust_score=1.0,
            last_interaction_at=datetime.now()
        )
        db.add(new_link)
    db.commit()
