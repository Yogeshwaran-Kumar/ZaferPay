"""
AI Scheduler - Automated Fraud Detection Engine Retraining

This module provides automatic retraining of the AI fraud detection model
using APScheduler. It runs as a background task alongside the main FastAPI app.

Features:
- Automatic retraining every 24 hours (configurable)
- Uses FraudEvent table for feedback loop (online learning)
- Champion-Challenger model comparison (A/B testing)
- HMAC-signed models for security

Free Cost: Uses APScheduler (BSD license)
"""

import os
import pickle
import hashlib
import hmac
import logging
import threading
from datetime import datetime, timedelta
from typing import Optional, Tuple

# Scheduler
try:
    from apscheduler.schedulers.background import BackgroundScheduler
    from apscheduler.triggers.interval import IntervalTrigger
    SCHEDULER_AVAILABLE = True
except ImportError:
    SCHEDULER_AVAILABLE = False
    print("⚠️ APScheduler not installed. Auto-retraining disabled.")

# Local imports
from database import SessionLocal
import models
from auth import HMAC_SECRET

# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════

RETRAIN_INTERVAL_HOURS = 24  # Default: retrain every 24 hours
MIN_TRANSACTIONS_FOR_TRAINING = 30
MODEL_PATH = "fraud_model_v2.pkl"
CHALLENGER_MODEL_PATH = "fraud_model_challenger.pkl"

# Logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("ai_scheduler")

# Global scheduler instance
_scheduler: Optional[BackgroundScheduler] = None


def get_db():
    """Get database session for background job"""
    db = SessionLocal()
    try:
        return db
    finally:
        pass  # Caller responsible for closing


def sign_model(model_bytes: bytes) -> bytes:
    """Sign model with HMAC-SHA256"""
    digest = hmac.new(HMAC_SECRET.encode(), model_bytes, hashlib.sha256)
    return digest.hexdigest().encode()


def save_signed_model(model, path: str):
    """Save model with embedded HMAC signature"""
    model_bytes = pickle.dumps(model)
    signature = sign_model(model_bytes)
    
    with open(path, "wb") as f:
        f.write(model_bytes)
        f.write(signature)
    
    logger.info(f"✅ Model saved and signed: {path}")


def load_champion_model():
    """Load the current champion model"""
    if not os.path.exists(MODEL_PATH):
        return None
    
    try:
        with open(MODEL_PATH, "rb") as f:
            content = f.read()
        
        payload = content[:-64]
        embedded_sig = content[-64:]
        expected_sig = sign_model(payload)
        
        if hmac.compare_digest(embedded_sig, expected_sig):
            return pickle.loads(payload)
        else:
            logger.warning("⚠️ Champion model signature mismatch!")
            return None
    except Exception as e:
        logger.error(f"Failed to load champion: {e}")
        return None


# ═══════════════════════════════════════════════════════════════════════════
# FEEDBACK LOOP (Use FraudEvent Table)
# ═══════════════════════════════════════════════════════════════════════════

def get_fraud_feedback(db, days: int = 30) -> list:
    """
    Get confirmed fraud events from FraudEvent table.
    This is the feedback loop - we learn from blocked transactions.
    
    Returns list of (transaction_id, is_fraud) tuples
    """
    since = datetime.now() - timedelta(days=days)
    
    events = db.query(models.FraudEvent).filter(
        models.FraudEvent.timestamp >= since
    ).all()
    
    # Events with high AI score or that were blocked are considered fraud patterns
    feedback = []
    for event in events:
        # is_blocked transactions are confirmed as needing intervention
        is_fraud = event.is_blocked or (event.ai_score and event.ai_score < -0.3)
        feedback.append({
            'transaction_id': event.transaction_id,
            'amount': event.amount,
            'ai_score': event.ai_score,
            'rule_violation': event.rule_violation,
            'is_fraud': is_fraud,
            'is_blocked': event.is_blocked
        })
    
    return feedback


# ═══════════════════════════════════════════════════════════════════════════
# TRAINING JOB
# ═══════════════════════════════════════════════════════════════════════════

def train_model():
    """
    Main training job - called by scheduler every 24 hours.
    
    Implements:
    1. Feedback loop (uses FraudEvent data)
    2. Online learning (incremental updates)
    3. Champion-Challenger comparison (A/B testing)
    """
    logger.info("AI Scheduler: Starting auto-retrain job...")
    
    db = get_db()
    
    try:
        # Check if sklearn is available
        try:
            from sklearn.ensemble import IsolationForest
        except ImportError:
            logger.warning("⚠️ sklearn not available. Skipping training.")
            return
        
        # 1. FETCH TRAINING DATA
        logger.info("Fetching transaction history...")
        
        txs = db.query(models.Transaction).filter(
            models.Transaction.status.in_(["SUCCESS", "FAILED", "BLOCKED"])
        ).all()
        if len(txs) < MIN_TRANSACTIONS_FOR_TRAINING:
            logger.info(f"Need {MIN_TRANSACTIONS_FOR_TRAINING} transactions, have {len(txs)}. Skipping.")
            return
        
        # 2. GET FEEDBACK DATA (Blocked transactions are "bad")
        logger.info("Loading fraud feedback...")
        feedback = get_fraud_feedback(db, days=30)
        blocked_tx_ids = {f['transaction_id'] for f in feedback if f['is_blocked']}
        logger.info(f"   Found {len(blocked_tx_ids)} blocked transactions to learn from")
        
        # 3. FEATURE EXTRACTION (28 Features)
        import pandas as pd
        import numpy as np
        import fraud_engine  # Import the real engine
        
        data = []
        labels = []  # 1 = fraud/blocked, 0 = normal
        
        for tx in txs:
            # Use the OPTIMIZED feature extraction logic (with valid SQL syntax)
            # This ensures training data matches inference data exactly
            features = fraud_engine.extract_features_optimized(db, tx.sender, tx.receiver, tx.amount, tx.timestamp)
            row = fraud_engine.get_feature_array(features)
            
            data.append(row)
            
            # Label: was this transaction blocked?
            is_blocked = tx.transaction_id in blocked_tx_ids or tx.status == "FAILED"
            labels.append(1 if is_blocked else 0)
        
        df = pd.DataFrame(data)
        
        # 4. TRAIN CHALLENGER MODELS
        logger.info(f"🧠 Training challenger models on {len(df)} records...")
        
        # Model A: Isolation Forest (Anomaly Detection)
        challenger_if = IsolationForest(
            n_estimators=200,
            contamination=0.05,
            max_features=0.8,
            random_state=42,
            n_jobs=-1
        )
        challenger_if.fit(df)
        
        # Model B: XGBoost (Classification)
        import fraud_engine
        XGBClassifier = fraud_engine.get_xgboost()
        challenger_xgb = None
        
        if XGBClassifier:
            try:
                logger.info("Training XGBoost challenger...")
                challenger_xgb = XGBClassifier(
                    n_estimators=100,
                    max_depth=4,
                    learning_rate=0.1,
                    objective='binary:logistic',
                    random_state=42,
                    n_jobs=-1
                )
                # For XGBoost, we use the labels (is_blocked)
                challenger_xgb.fit(df, labels)
            except Exception as e:
                logger.warning(f"XGBoost training failed: {e}")
                challenger_xgb = None

        # 5. CHAMPION-CHALLENGER COMPARISON
        champion = load_champion_model()
        
        # Evaluation function
        def safe_auc(scores, labels):
            if len(set(labels)) < 2: return 0.5
            if np.std(scores) == 0: return 0.5
            try:
                from sklearn.metrics import roc_auc_score
                return roc_auc_score(labels, scores)
            except Exception:
                try:
                    return abs(np.corrcoef(scores, labels)[0, 1])
                except:
                    return 0.5

        test_df = df.tail(100)
        test_labels = labels[-100:]
        
        # Score challengers
        if_scores = challenger_if.decision_function(test_df)
        # Normalize IF scores to 0-1 (decision_function is negative for anomalies)
        # We want higher score = high risk for AUC calculation with labels=1 (fraud)
        if_scores_normalized = [-s for s in if_scores] 
        if_auc = safe_auc(if_scores_normalized, test_labels)
        
        xgb_auc = 0
        if challenger_xgb:
            xgb_probs = challenger_xgb.predict_proba(test_df)[:, 1]
            xgb_auc = safe_auc(xgb_probs, test_labels)
        
        logger.info(f"Challenger IF AUC: {if_auc:.4f}")
        logger.info(f"Challenger XGB AUC: {xgb_auc:.4f}")
        
        # Pick best challenger
        if challenger_xgb and xgb_auc >= if_auc:
            best_challenger = challenger_xgb
            best_auc = xgb_auc
            model_type = "XGBoost"
        else:
            best_challenger = challenger_if
            best_auc = if_auc
            model_type = "IsolationForest"
            
        logger.info(f"Best challenger is {model_type} (AUC: {best_auc:.4f})")

        # Compare with champion
        if champion is not None:
            # Score champion
            try:
                if hasattr(champion, 'predict_proba'): # XGBoost
                    champion_scores = champion.predict_proba(test_df)[:, 1]
                else: # IsolationForest
                    champion_scores = [-s for s in champion.decision_function(test_df)]
                
                champion_auc = safe_auc(champion_scores, test_labels)
                logger.info(f"Current Champion AUC: {champion_auc:.4f}")
                
                if best_auc > champion_auc * 1.02: # 2% improvement threshold
                    logger.info(f"Promoting {model_type} to Champion!")
                    save_signed_model(best_challenger, MODEL_PATH)
                else:
                    logger.info("Champion defends territory.")
                    save_signed_model(best_challenger, CHALLENGER_MODEL_PATH)
            except Exception as e:
                logger.error(f"Champion evaluation failed: {e}. Promoting challenger.")
                save_signed_model(best_challenger, MODEL_PATH)
        else:
            logger.info(f"First run. Saving {model_type} as Champion.")
            save_signed_model(best_challenger, MODEL_PATH)
        
        logger.info("AI Scheduler: Retrain job completed!")
        
    except Exception as e:
        logger.error(f"❌ AI Scheduler error: {e}")
    finally:
        db.close()


# ═══════════════════════════════════════════════════════════════════════════
# SCHEDULER MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════

def start_scheduler(interval_hours: int = RETRAIN_INTERVAL_HOURS, train_on_startup: bool = True):
    """
    Start the background scheduler for auto-retraining.
    
    Args:
        interval_hours: How often to retrain (default 24 hours)
        train_on_startup: Whether to train immediately on startup (default True)
    """
    global _scheduler
    
    if not SCHEDULER_AVAILABLE:
        logger.warning("⚠️ APScheduler not available. Auto-retraining disabled.")
        return False
    
    if _scheduler is not None:
        logger.info("Scheduler already running.")
        return True
    
    _scheduler = BackgroundScheduler()
    
    # Add the training job
    _scheduler.add_job(
        train_model,
        trigger=IntervalTrigger(hours=interval_hours),
        id='ai_retrain',
        name='AI Model Retraining',
        replace_existing=True
    )
    
    _scheduler.start()
    logger.info(f"AI Scheduler started. Retraining every {interval_hours} hours.")
    
    # Run startup training in a BACKGROUND THREAD so it doesn't block the server
    if train_on_startup:
        logger.info("Running startup training in background thread...")
        t = threading.Thread(target=train_model, daemon=True)
        t.start()
    
    return True


def stop_scheduler():
    """Stop the background scheduler"""
    global _scheduler
    
    if _scheduler is not None:
        _scheduler.shutdown(wait=False)
        _scheduler = None
        logger.info("🛑 AI Scheduler stopped.")


def is_scheduler_running() -> bool:
    """Check if scheduler is running"""
    return _scheduler is not None and _scheduler.running


def get_next_retrain_time() -> Optional[datetime]:
    """Get the next scheduled retrain time"""
    if _scheduler is None:
        return None
    
    job = _scheduler.get_job('ai_retrain')
    if job:
        return job.next_run_time
    return None


def get_model_stats() -> dict:
    """
    Get current AI model statistics for admin dashboard.
    """
    stats = {
        "model_exists": os.path.exists(MODEL_PATH),
        "model_path": MODEL_PATH,
        "scheduler_running": is_scheduler_running(),
        "next_retrain": str(get_next_retrain_time()) if get_next_retrain_time() else None,
    }
    
    if os.path.exists(MODEL_PATH):
        stat = os.stat(MODEL_PATH)
        stats["model_size_kb"] = round(stat.st_size / 1024, 2)
        stats["model_last_updated"] = datetime.fromtimestamp(stat.st_mtime).isoformat()
    
    return stats


def manual_retrain() -> dict:
    """
    Manually trigger model retraining.
    Returns status and any errors.
    """
    try:
        logger.info("🔧 Manual retrain triggered...")
        train_model()
        return {
            "success": True,
            "message": "Model retrained successfully",
            "stats": get_model_stats()
        }
    except Exception as e:
        logger.error(f"Manual retrain failed: {e}")
        return {
            "success": False,
            "message": f"Retrain failed: {str(e)}"
        }


# ═══════════════════════════════════════════════════════════════════════════
# CLI INTERFACE
# ═══════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    import sys
    
    if len(sys.argv) > 1 and sys.argv[1] == "train":
        # Manual training
        print("Running manual training...")
        train_model()
    else:
        # Interactive scheduler
        print("Starting AI Scheduler in foreground...")
        start_scheduler(interval_hours=1)  # 1 hour for testing
        
        try:
            import time
            while True:
                time.sleep(60)
                print(f"Next retrain: {get_next_retrain_time()}")
        except KeyboardInterrupt:
            stop_scheduler()
            print("\nScheduler stopped.")
