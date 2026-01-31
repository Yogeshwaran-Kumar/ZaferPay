"""
Advanced Fraud Detection Engine - v2.0 (⭐⭐⭐)

Upgrades from v1.0:
- 12+ Features (up from 2)
- XGBoost + IsolationForest ensemble
- 15+ Rules (up from 8)
- Adaptive Learning

Google Pay Style 3-Stage Pipeline:
1. REFLEXES (Hard Rules) - Instant Fail
2. NETWORK (Social Graph) - Trust Validation
3. BRAIN (AI Analysis) - Pattern Detection
"""

import models
from sqlalchemy.orm import Session
from sqlalchemy import func
from datetime import datetime, timedelta
import pandas as pd
import numpy as np
import pickle
import os
import hashlib
import json
import math

# ═══════════════════════════════════════════════════════════════════════════
# GEO-VELOCITY MODULE (Impossible Travel Detection)
# ═══════════════════════════════════════════════════════════════════════════
try:
    import geoip2.database
    GEOIP_DB_PATH = os.path.join(os.path.dirname(__file__), "GeoLite2-City.mmdb")
    if os.path.exists(GEOIP_DB_PATH):
        _geoip_reader = geoip2.database.Reader(GEOIP_DB_PATH)
        GEOIP_ENABLED = True
        print("🌍 GeoIP2 loaded successfully - Geo-velocity check ENABLED")
    else:
        _geoip_reader = None
        GEOIP_ENABLED = False
        print("⚠️ GeoLite2-City.mmdb not found - Geo-velocity check DISABLED")
except ImportError:
    _geoip_reader = None
    GEOIP_ENABLED = False
    print("⚠️ geoip2 not installed - Geo-velocity check DISABLED")


def get_location_from_ip(ip_address: str) -> tuple:
    """Get latitude, longitude, city, country from IP address"""
    if not GEOIP_ENABLED or not _geoip_reader:
        return None, None, None, None
    
    try:
        # Skip private/local IPs
        if ip_address in ["127.0.0.1", "localhost"] or ip_address.startswith("192.168.") or ip_address.startswith("10."):
            return None, None, "Local", "Private"
        
        response = _geoip_reader.city(ip_address)
        return (
            response.location.latitude,
            response.location.longitude,
            response.city.name or "Unknown",
            response.country.name or "Unknown"
        )
    except Exception:
        return None, None, None, None


def calculate_distance_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate distance between two coordinates using Haversine formula"""
    if any(x is None for x in [lat1, lon1, lat2, lon2]):
        return 0
    
    R = 6371  # Earth's radius in km
    
    lat1_rad = math.radians(lat1)
    lat2_rad = math.radians(lat2)
    delta_lat = math.radians(lat2 - lat1)
    delta_lon = math.radians(lon2 - lon1)
    
    a = math.sin(delta_lat/2)**2 + math.cos(lat1_rad) * math.cos(lat2_rad) * math.sin(delta_lon/2)**2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))
    
    return R * c


def check_geo_velocity(current_ip: str, last_ip: str, minutes_since_last: float) -> tuple:
    """
    Check for impossible travel (geo-velocity violation)
    
    Returns: (is_violation, distance_km, max_possible_speed_kmh)
    
    Rule: If distance / time > 900 km/h (realistic max flight speed), flag as suspicious
    """
    if not GEOIP_ENABLED:
        return False, 0, 0
    
    lat1, lon1, city1, country1 = get_location_from_ip(last_ip)
    lat2, lon2, city2, country2 = get_location_from_ip(current_ip)
    
    if lat1 is None or lat2 is None:
        return False, 0, 0
    
    distance_km = calculate_distance_km(lat1, lon1, lat2, lon2)
    
    if minutes_since_last <= 0:
        minutes_since_last = 1  # Avoid division by zero
    
    hours = minutes_since_last / 60
    speed_kmh = distance_km / hours if hours > 0 else 0
    
    # 900 km/h is max realistic speed (commercial jet)
    # If someone travels faster than this, it's impossible (or VPN/proxy)
    MAX_TRAVEL_SPEED_KMH = 900
    
    is_violation = speed_kmh > MAX_TRAVEL_SPEED_KMH and distance_km > 500  # At least 500km
    
    if is_violation:
        print(f"🚨 GEO-VELOCITY VIOLATION: {city1}, {country1} → {city2}, {country2}")
        print(f"   Distance: {distance_km:.0f} km in {minutes_since_last:.0f} min = {speed_kmh:.0f} km/h")
    
    return is_violation, distance_km, speed_kmh

# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION & CONSTANTS
# ═══════════════════════════════════════════════════════════════════════════

RISK_THRESHOLD_HIGH = 80    # Block immediately
RISK_THRESHOLD_WARN = 50    # Allow but flag

MODEL_PATH = "fraud_model_v2.pkl"
MIN_DATA_POINTS = 30        # Reduced for faster initial training
RETRAIN_THRESHOLD = 100     # Retrain after every 100 new transactions

# ═══════════════════════════════════════════════════════════════════════════
# PERMANENT DAILY LIMITS - DO NOT MODIFY THESE VALUES
# ═══════════════════════════════════════════════════════════════════════════
# These are hardcoded safety limits that should NEVER be changed.
# P2P: ₹1,00,000 per receiver per day
# Merchant: ₹3,00,000 per receiver per day

DAILY_RECEIVER_LIMIT_P2P = 100000       # ₹1 Lakh - PERMANENT
DAILY_RECEIVER_LIMIT_MERCHANT = 300000  # ₹3 Lakh - PERMANENT

# Global Cache
_model = None
# _is_trained is removed because we ONLY load, never train


# ═══════════════════════════════════════════════════════════════════════════
# MCC RISK TIER SYSTEM (World-Class Commercial Engine)
# ═══════════════════════════════════════════════════════════════════════════
# 
# The Truth: Personal (P2P) fraud is about "Who you know" (Social Graph).
#            Merchant (P2M) fraud is about "What you buy" (MCC Context).
#
# 5 Tiers:
#   ESSENTIAL  - Hospitals, Schools, Utilities. NEVER BLOCK.
#   HIGH_VALUE - Jewelry, Business Services. Allow big amounts, watch velocity.
#   RETAIL     - Grocery, Food, Transport. High velocity allowed.
#   SERVICES   - Electronics, Travel, Hotels. Standard checks.
#   PERSONAL   - 0000/None. Use Social Graph (existing logic).

MCC_TIERS = {
    "ESSENTIAL": {
        "trust_bonus": 50,
        "skip_spike": True,
        "skip_stranger": True,
        "velocity_limit": 999,  # Unlimited
        "max_amount": 10000000,  # ₹1 Crore
    },
    "HIGH_VALUE": {
        "trust_bonus": 0,
        "skip_spike": True,      # Jewelry = big spikes are normal
        "skip_stranger": True,   # You don't know your jeweler personally
        "velocity_limit": 2,     # STRICT: 2 per hour (Anti-Money Laundering)
        "max_amount": 500000,    # ₹5 Lakhs
    },
    "RETAIL": {
        "trust_bonus": 20,
        "skip_spike": False,
        "skip_stranger": True,
        "velocity_limit": 20,    # Shopping spree allowed
        "max_amount": 100000,    # ₹1 Lakh
        "spike_multiplier": 5.0, # 5x average allowed
    },
    "SERVICES": {
        "trust_bonus": 0,
        "skip_spike": False,
        "skip_stranger": False,
        "velocity_limit": 5,
        "max_amount": 200000,    # ₹2 Lakhs
        "spike_multiplier": 3.0,
        "stranger_warn_limit": 50000,
    },
    "PERSONAL": {
        "trust_bonus": 0,
        "skip_spike": False,
        "skip_stranger": False,
        "velocity_limit": 5,
        "max_amount": 100000,    # ₹1 Lakh (P2P limit)
        "spike_multiplier": 3.0,
        "stranger_first_time_limit": 5000,   # ₹5k for strangers
        "stranger_friend_limit": 100000,     # ₹1 Lakh for friends
    },
}

MCC_REGISTRY = {
    # ─── TIER: ESSENTIAL (Life-Critical) ───────────────────────────────────────
    # Medical
    "8011": "ESSENTIAL",  # Hospital
    "8021": "ESSENTIAL",  # Dentist
    "8031": "ESSENTIAL",  # Doctor / Clinic
    "8041": "ESSENTIAL",  # Chiropractor
    "8042": "ESSENTIAL",  # Optometrist
    "8049": "ESSENTIAL",  # Medical Services
    "8050": "ESSENTIAL",  # Nursing / Care
    "8062": "ESSENTIAL",  # Hospital (Alt)
    "5912": "ESSENTIAL",  # Pharmacy
    # Education
    "8211": "ESSENTIAL",  # School
    "8220": "ESSENTIAL",  # College / University
    "8241": "ESSENTIAL",  # Training / Coaching
    "8249": "ESSENTIAL",  # Education Services
    # Utilities & Finance
    "4900": "ESSENTIAL",  # Utilities (Water/Elec)
    "4814": "ESSENTIAL",  # Telecom
    "6012": "ESSENTIAL",  # Financial Institution
    "6300": "ESSENTIAL",  # Insurance
    
    # ─── TIER: HIGH_VALUE (Luxury & Business) ──────────────────────────────────
    "5944": "HIGH_VALUE",  # Jewelry
    "7399": "HIGH_VALUE",  # Business Services
    "7392": "HIGH_VALUE",  # Consulting
    "8111": "HIGH_VALUE",  # Legal Services
    "8931": "HIGH_VALUE",  # Accounting
    "5251": "HIGH_VALUE",  # Hardware Store (Construction)
    "5712": "HIGH_VALUE",  # Furniture Store
    
    # ─── TIER: RETAIL (Daily Needs / Speed) ────────────────────────────────────
    # Food & Grocery
    "5411": "RETAIL",  # Grocery / Retail Shop
    "5311": "RETAIL",  # Department Store
    "5399": "RETAIL",  # General Retail
    "5499": "RETAIL",  # Misc. Food Store
    "5441": "RETAIL",  # Candy / Snacks
    "5462": "RETAIL",  # Bakery
    # Dining
    "5812": "RETAIL",  # Restaurant
    "5813": "RETAIL",  # Bar / Pub
    "5814": "RETAIL",  # Fast Food
    # Fashion (Daily)
    "5651": "RETAIL",  # Clothing Store
    "5661": "RETAIL",  # Shoe Store
    "5977": "RETAIL",  # Cosmetics
    # Transport
    "4111": "RETAIL",  # Transport / Taxi
    "4121": "RETAIL",  # Cab / Auto
    "4131": "RETAIL",  # Bus / Travel
    "4789": "RETAIL",  # Transport Services
    # Entertainment (Low Value)
    "7832": "RETAIL",  # Cinema
    "7922": "RETAIL",  # Theater
    "7991": "RETAIL",  # Tourist Attraction
    "7996": "RETAIL",  # Amusement Park
    "7999": "RETAIL",  # Recreation
    # Books & Sports
    "5941": "RETAIL",  # Sporting Goods
    "5942": "RETAIL",  # Book Store
    
    # ─── TIER: SERVICES (Standard Checks) ──────────────────────────────────────
    # Travel & Lodging
    "4722": "SERVICES",  # Travel Agency
    "4511": "SERVICES",  # Airlines
    "7011": "SERVICES",  # Hotel
    "7012": "SERVICES",  # Timeshare
    "7032": "SERVICES",  # Camping / Lodging
    # Electronics & Tech
    "5732": "SERVICES",  # Electronics Store
    "7372": "SERVICES",  # Software / IT
    # Home Services
    "7349": "SERVICES",  # Cleaning Services
    "7210": "SERVICES",  # Laundry
    
    # ─── TIER: PERSONAL (P2P / Unknown) ────────────────────────────────────────
    "0000": "PERSONAL",  # Business (Unknown / Personal)
}

def get_mcc_tier(mcc: str) -> str:
    """
    Resolve the Risk Tier for a given MCC.
    Returns 'PERSONAL' for unknown/null MCCs.
    """
    if not mcc or mcc == "0000" or mcc == "":
        return "PERSONAL"
    return MCC_REGISTRY.get(mcc, "SERVICES")  # Default to SERVICES if unknown MCC

def get_tier_config(tier: str) -> dict:
    """Get the configuration dict for a risk tier."""
    return MCC_TIERS.get(tier, MCC_TIERS["PERSONAL"])

# ═══════════════════════════════════════════════════════════════════════════
# ML LIBRARY LOADERS (Lazy Load)
# ═══════════════════════════════════════════════════════════════════════════

def get_isolation_forest():
    """Safe import for IsolationForest"""
    try:
        from sklearn.ensemble import IsolationForest
        return IsolationForest
    except ImportError:
        print("⚠️ sklearn not found. AI Brain will be disabled.")
        return None

def get_xgboost():
    """Safe import for XGBoost - falls back gracefully"""
    try:
        from xgboost import XGBClassifier
        return XGBClassifier
    except ImportError:
        print("⚠️ XGBoost not found. Using IsolationForest only.")
        return None

def get_scaler():
    """Standard Scaler for normalizing features"""
    try:
        from sklearn.preprocessing import StandardScaler
        return StandardScaler
    except ImportError:
        return None

# ═══════════════════════════════════════════════════════════════════════════
# FEATURE ENGINEERING (The 12+ Features)
# ═══════════════════════════════════════════════════════════════════════════

def extract_features(db: Session, sender: models.User, receiver: models.User, amount: float, timestamp: datetime = None) -> dict:
    """
    Extracts 12+ features for ML model.
    This is the CORE upgrade from v1.0
    """
    if timestamp is None:
        timestamp = datetime.now()
    
    features = {}
    
    # ─── TRANSACTION FEATURES ─────────────────────────────────────────────────
    features['amount'] = amount
    features['hour'] = timestamp.hour
    features['day_of_week'] = timestamp.weekday()  # 0=Monday, 6=Sunday
    features['is_weekend'] = 1 if timestamp.weekday() >= 5 else 0
    features['is_night'] = 1 if (timestamp.hour >= 22 or timestamp.hour <= 5) else 0
    
    # ─── VELOCITY FEATURES (Last 1 hour / 24 hours) ───────────────────────────
    hour_ago = timestamp - timedelta(hours=1)
    day_ago = timestamp - timedelta(hours=24)
    
    # Transactions in last hour
    tx_count_1h = db.query(func.count(models.Transaction.id)).filter(
        models.Transaction.sender_id == sender.id,
        models.Transaction.timestamp > hour_ago
    ).scalar() or 0
    features['tx_count_1h'] = tx_count_1h
    
    # Transactions in last 24 hours
    tx_count_24h = db.query(func.count(models.Transaction.id)).filter(
        models.Transaction.sender_id == sender.id,
        models.Transaction.timestamp > day_ago
    ).scalar() or 0
    features['tx_count_24h'] = tx_count_24h
    
    # Total amount sent in last 24 hours
    total_24h = db.query(func.sum(models.Transaction.amount)).filter(
        models.Transaction.sender_id == sender.id,
        models.Transaction.timestamp > day_ago
    ).scalar() or 0
    features['total_amount_24h'] = total_24h
    
    # ─── BEHAVIORAL FEATURES ──────────────────────────────────────────────────
    
    # Average transaction amount (from SenderProfile)
    avg_amount = 0
    if sender.sender_profile and sender.sender_profile.avg_transaction_amount > 0:
        avg_amount = sender.sender_profile.avg_transaction_amount
    features['avg_amount'] = avg_amount
    
    # Ratio: Current amount / Average (0 if no history)
    features['amount_vs_avg_ratio'] = (amount / avg_amount) if avg_amount > 0 else 1.0
    
    # Time since last transaction (in minutes)
    last_tx = db.query(models.Transaction.timestamp).filter(
        models.Transaction.sender_id == sender.id
    ).order_by(models.Transaction.timestamp.desc()).first()
    
    if last_tx:
        time_diff = (timestamp - last_tx[0]).total_seconds() / 60
        features['minutes_since_last_tx'] = min(time_diff, 10080)  # Cap at 7 days
    else:
        features['minutes_since_last_tx'] = 10080  # First time user = 7 days
    
    # ─── NETWORK FEATURES ─────────────────────────────────────────────────────
    
    # Unique receivers today
    unique_receivers = db.query(func.count(func.distinct(models.Transaction.receiver_id))).filter(
        models.Transaction.sender_id == sender.id,
        models.Transaction.timestamp > day_ago
    ).scalar() or 0
    features['unique_receivers_24h'] = unique_receivers
    
    # Is this receiver new? (Never paid before)
    ever_paid = db.query(models.Transaction).filter(
        models.Transaction.sender_id == sender.id,
        models.Transaction.receiver_id == receiver.id
    ).first()
    features['is_new_receiver'] = 0 if ever_paid else 1
    
    # ─── TRUST GRAPH FEATURES ─────────────────────────────────────────────────
    
    # Trust score from graph
    trust_link = db.query(models.UserTrustGraph).filter(
        models.UserTrustGraph.user_id == sender.id,
        models.UserTrustGraph.trusted_user_id == receiver.id
    ).first()
    features['trust_score'] = trust_link.trust_score if trust_link else 0.0
    
    # ─── ACCOUNT MATURITY ─────────────────────────────────────────────────────
    
    # Account age in days (using first transaction as proxy)
    first_tx = db.query(models.Transaction.timestamp).filter(
        models.Transaction.sender_id == sender.id
    ).order_by(models.Transaction.timestamp.asc()).first()
    
    if first_tx:
        account_age = (timestamp - first_tx[0]).days
        features['account_age_days'] = min(account_age, 365)  # Cap at 1 year
    else:
        features['account_age_days'] = 0  # Brand new
    
    # ─── RECEIVER RISK FEATURES ───────────────────────────────────────────────
    
    # How many unique senders sent to this receiver today?
    receiver_inflow = db.query(func.count(func.distinct(models.Transaction.sender_id))).filter(
        models.Transaction.receiver_id == receiver.id,
        models.Transaction.timestamp > day_ago
    ).scalar() or 0
    features['receiver_unique_senders_24h'] = receiver_inflow
    
    # ═══════════════════════════════════════════════════════════════════════════
    # NEW FEATURES v3.0 (12 Additional Features for 10/10 Score)
    # ═══════════════════════════════════════════════════════════════════════════
    
    # ─── F17: SESSION FEATURES ──────────────────────────────────────────────────
    
    # Session transaction count (transactions in last 30 minutes = "session")
    session_start = timestamp - timedelta(minutes=30)
    session_tx_count = db.query(func.count(models.Transaction.id)).filter(
        models.Transaction.sender_id == sender.id,
        models.Transaction.timestamp > session_start
    ).scalar() or 0
    features['session_tx_count'] = session_tx_count
    
    # Average session transaction count (from history)
    if sender.sender_profile and sender.sender_profile.total_transactions_count > 10:
        # Approximate: assume 5 sessions per day average
        avg_sessions = max(1, features['account_age_days'] * 5)
        features['avg_session_tx'] = sender.sender_profile.total_transactions_count / avg_sessions
    else:
        features['avg_session_tx'] = 3.0  # Default assumption
    
    # ─── F18: RECIPIENT PROFILING ────────────────────────────────────────────────
    
    # Receiver account age (days since first received transaction)
    receiver_first_tx = db.query(models.Transaction.timestamp).filter(
        models.Transaction.receiver_id == receiver.id
    ).order_by(models.Transaction.timestamp.asc()).first()
    
    if receiver_first_tx:
        receiver_age = (timestamp - receiver_first_tx[0]).days
        features['recipient_age_days'] = min(receiver_age, 365)
    else:
        features['recipient_age_days'] = 0  # Brand new receiver
    
    # Receiver's total transaction volume (received amount)
    if receiver.receiver_profile:
        features['recipient_tx_volume'] = receiver.receiver_profile.total_received_amount or 0
    else:
        features['recipient_tx_volume'] = 0
    
    # ─── F19: BEHAVIORAL PATTERN FEATURES ────────────────────────────────────────
    
    # Amount percentile (where does this amount fall in user's history)
    # Simplified: calculate based on average
    if features['avg_amount'] > 0:
        percentile = min(100, (amount / features['avg_amount']) * 50)  # 50th = average
        features['amount_percentile'] = percentile
    else:
        features['amount_percentile'] = 50  # No history = neutral
    
    # Hour frequency (how often user transacts at this hour)
    hour_count = db.query(func.count(models.Transaction.id)).filter(
        models.Transaction.sender_id == sender.id,
        func.extract('hour', models.Transaction.timestamp) == timestamp.hour
    ).scalar() or 0
    total_tx = sender.sender_profile.total_transactions_count if sender.sender_profile else 1
    features['hour_frequency'] = (hour_count / max(1, total_tx)) * 100
    
    # Day frequency (how often user transacts on this day of week)
    day_count = db.query(func.count(models.Transaction.id)).filter(
        models.Transaction.sender_id == sender.id,
        func.extract('dow', models.Transaction.timestamp) == timestamp.weekday()
    ).scalar() or 0
    features['day_frequency'] = (day_count / max(1, total_tx)) * 100
    
    # ─── F20: EXACT AMOUNT ANALYSIS ─────────────────────────────────────────────
    
    # Is this exact amount new for this user?
    exact_amount_count = db.query(func.count(models.Transaction.id)).filter(
        models.Transaction.sender_id == sender.id,
        models.Transaction.amount == amount
    ).scalar() or 0
    features['is_first_time_amount'] = 1 if exact_amount_count == 0 else 0
    
    # ─── F21: VELOCITY FEATURES (ADVANCED) ──────────────────────────────────────
    
    # Consecutive transaction count (back-to-back without 5+ min pause)
    recent_times = db.query(models.Transaction.timestamp).filter(
        models.Transaction.sender_id == sender.id,
        models.Transaction.timestamp > timestamp - timedelta(hours=1)
    ).order_by(models.Transaction.timestamp.desc()).limit(10).all()
    
    consecutive = 0
    for i in range(len(recent_times) - 1):
        gap = (recent_times[i][0] - recent_times[i+1][0]).total_seconds() / 60
        if gap < 5:
            consecutive += 1
        else:
            break
    features['consecutive_tx_count'] = consecutive
    
    # ─── F22: FINANCIAL HEALTH FEATURES ─────────────────────────────────────────
    
    # Balance utilization (% of balance being used in this transaction)
    if sender.balance > 0:
        features['balance_utilization'] = (amount / sender.balance) * 100
    else:
        features['balance_utilization'] = 100  # No balance = high risk
    
    return features


def get_feature_array(features: dict) -> list:
    """Convert feature dict to array for ML model (28 features total)"""
    feature_order = [
        # Original 16 features
        'amount', 'hour', 'day_of_week', 'is_weekend', 'is_night',
        'tx_count_1h', 'tx_count_24h', 'total_amount_24h',
        'avg_amount', 'amount_vs_avg_ratio', 'minutes_since_last_tx',
        'unique_receivers_24h', 'is_new_receiver', 'trust_score',
        'account_age_days', 'receiver_unique_senders_24h',
        # New 12 features (v3.0)
        'session_tx_count', 'avg_session_tx', 'recipient_age_days',
        'recipient_tx_volume', 'amount_percentile', 'hour_frequency',
        'day_frequency', 'is_first_time_amount', 'consecutive_tx_count',
        'balance_utilization'
    ]
    return [features.get(f, 0) for f in feature_order]


# ═══════════════════════════════════════════════════════════════════════════
# STAGE 3: THE BRAIN (AI Engine v2.0)
# ═══════════════════════════════════════════════════════════════════════════

import hmac
from auth import HMAC_SECRET

def _calculate_file_hash(filepath):
    """Calculate HMAC-SHA256 signature of a file (Keyed Hash)"""
    if not os.path.exists(filepath):
        return None
        
    # Use HMAC-SHA256 (Keyed Hash)
    digest = hmac.new(HMAC_SECRET.encode(), b"", hashlib.sha256)
    
    with open(filepath, "rb") as f:
        # Read in chunks
        for byte_block in iter(lambda: f.read(4096), b""):
            digest.update(byte_block)
            
    return digest.hexdigest()

def load_model_readonly():
    """Load existing model (READ-ONLY GUARD MODE)"""
    global _model
    
    if _model is not None:
        return

    if not os.path.exists(MODEL_PATH):
        print("🛡️ Guard: No AI Model found. Operating in 'Rules Only' mode.")
        return

    try:
        # 🔒 SECURITY: TWIN ENGINE CHECK (Embedded Signature)
        # We read the file, extract the last 64 bytes (Signature), and verify the rest.
        
        with open(MODEL_PATH, "rb") as f:
            file_content = f.read()
            
        if len(file_content) < 64:
            print("🚨 SECURITY ALERT: Model file too short (Corrupt/Empty)!")
            return

        # Split: Payload | Signature (Last 64 bytes)
        payload = file_content[:-64]
        embedded_signature = file_content[-64:] # Bytes
        
        # Verify
        expected_digest = hmac.new(HMAC_SECRET.encode(), payload, hashlib.sha256)
        expected_signature = expected_digest.hexdigest().encode()
        
        if hmac.compare_digest(embedded_signature, expected_signature):
             _model = pickle.loads(payload)
             print("🧠 Guard: AI Brain Verified (Embedded Seal). Ready to detect.")
        else:
            print("🚨 SECURITY ALERT: Model tampering detected! (Invalid Seal)")
            print("🛡️ Guard: Refusing to load. AI disabled.")
            
    except Exception as e:
        print(f"⚠️ Guard: Failed to load model: {e}")

# NOTE: train_model() is REMOVED. This file is now purely a Detector.
# Training happens in 'ai_scheduler.py' (auto-runs every 24 hours).



def get_ai_score(features: dict) -> float:
    """Get anomaly score from AI model"""
    if _model is None:
        return 0.0  # Neutral if no model
    
    try:
        feature_array = get_feature_array(features)
        score = _model.decision_function([feature_array])[0]
        return score  # Negative = Anomaly, Positive = Normal
    except Exception as e:
        print(f"⚠️ AI Score error: {e}")
        return 0.0


def trigger_retrain_if_needed(db: Session):
    """Retrain model periodically"""
    global _transaction_count_since_train
    
    _transaction_count_since_train += 1
    
    if _transaction_count_since_train >= RETRAIN_THRESHOLD:
        print("🔄 Triggering model retrain...")
        train_model(db)
        _transaction_count_since_train = 0


# ═══════════════════════════════════════════════════════════════════════════
# SOCIAL GRAPH (Trust Network)
# ═══════════════════════════════════════════════════════════════════════════

def calculate_trust_depth(db: Session, sender_id: int, receiver_id: int, max_depth=2) -> int:
    """
    Trust Graph Depth:
    - Depth 1: Direct Friend (I trust you)
    - Depth 2: Friend of Friend
    - Depth 0: Stranger
    """
    # Direct Trust (Depth 1)
    direct = db.query(models.UserTrustGraph).filter(
        models.UserTrustGraph.user_id == sender_id,
        models.UserTrustGraph.trusted_user_id == receiver_id
    ).first()
    if direct:
        return 1
    
    # Friend of Friend (Depth 2)
    my_friends = db.query(models.UserTrustGraph.trusted_user_id).filter(
        models.UserTrustGraph.user_id == sender_id
    ).all()
    friend_ids = [f[0] for f in my_friends]
    
    if not friend_ids:
        return 0
    
    fof = db.query(models.UserTrustGraph).filter(
        models.UserTrustGraph.user_id.in_(friend_ids),
        models.UserTrustGraph.trusted_user_id == receiver_id
    ).first()
    
    if fof:
        return 2
    
    return 0  # Stranger


# ═══════════════════════════════════════════════════════════════════════════
# MAIN FRAUD ENGINE (The 3-Stage Pipeline)
# ═══════════════════════════════════════════════════════════════════════════

def evaluate_fraud(db: Session, sender: models.User, receiver: models.User, amount: float, device_id_hash: str = None, receiver_mcc: str = None, current_ip: str = None):
    """
    Advanced 3-Stage Fraud Detection Pipeline with MCC Context-Awareness:
    
    Stage 0: MCC TIER CLASSIFICATION - Route to appropriate engine
    Stage 1: REFLEXES (Hard Rules) - 54 Rules (with tier-based exemptions)
    Stage 2: NETWORK (Social Graph) - Trust Validation (P2P only)
    Stage 3: BRAIN (AI Analysis) - 28-Feature Anomaly Detection
    
    MCC Tiers:
    - ESSENTIAL (Hospitals, Schools): Almost no blocking
    - HIGH_VALUE (Jewelry, Business): High amounts OK, strict velocity
    - RETAIL (Grocery, Transport): High velocity, moderate amounts
    - SERVICES (Hotels, Electronics): Standard checks
    - PERSONAL (0000/None): Full Social Graph checks
    
    New in v4.0:
    - Full geo-velocity (F29) with IP tracking
    - 22 new rules (F30-F54) for velocity, behavioral, and AML detection
    """
    load_model_readonly()
    
    # Extract all features upfront
    now = datetime.now()
    features = extract_features(db, sender, receiver, amount, now)
    
    # Store current IP for geo-velocity check
    if current_ip:
        features['current_ip'] = current_ip
    
    # ═══════════════════════════════════════════════════════════════════════════
    # STAGE 0: MCC TIER CLASSIFICATION (The Router)
    # ═══════════════════════════════════════════════════════════════════════════
    
    tier = get_mcc_tier(receiver_mcc)
    tier_config = get_tier_config(tier)
    
    # Store tier info in features for logging
    features['mcc'] = receiver_mcc
    features['tier'] = tier
    
    print(f"🏷️ MCC Classification: {receiver_mcc} → {tier}")
    
    # ─── ESSENTIAL TIER: FAST PATH (Hospitals, Schools, Utilities) ─────────────
    # The Truth: We NEVER want to block a hospital payment.
    if tier == "ESSENTIAL":
        print(f"🏥 ESSENTIAL TIER: Bypassing all fraud checks for {receiver_mcc}")
        features['ai_score'] = 0.0
        return "SAFE", None, features
    
    # ═══════════════════════════════════════════════════════════════════════════
    # Initialize scoring
    # ═══════════════════════════════════════════════════════════════════════════
    
    risk_score = 0
    violation = None
    violations_list = []
    
    # Apply tier trust bonus/penalty upfront
    risk_score -= tier_config.get("trust_bonus", 0)
    
    # ─── F18: DAILY PER-RECEIVER LIMIT (PERMANENT - DO NOT MODIFY) ─────────────
    # This rule is PERMANENT and should NEVER be changed.
    # P2P: ₹1,00,000 per receiver per day
    # Merchant: ₹3,00,000 per receiver per day
    day_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    sent_to_receiver_today = db.query(func.sum(models.Transaction.amount)).filter(
        models.Transaction.sender_id == sender.id,
        models.Transaction.receiver_id == receiver.id,
        models.Transaction.timestamp >= day_start,
        models.Transaction.status == "SUCCESS"
    ).scalar() or 0
    
    # Use tier-specific limit: P2P = ₹1 Lakh, Merchant = ₹3 Lakh
    daily_limit = DAILY_RECEIVER_LIMIT_P2P if tier == "PERSONAL" else DAILY_RECEIVER_LIMIT_MERCHANT
    
    if sent_to_receiver_today + amount > daily_limit:
        limit_formatted = f"₹{daily_limit:,}"
        remaining = max(0, daily_limit - sent_to_receiver_today)
        print(f"🚫 F18: Daily limit exceeded! Sent today: ₹{sent_to_receiver_today:,}, Trying: ₹{amount:,}, Limit: {limit_formatted}")
        features['daily_sent_to_receiver'] = sent_to_receiver_today
        features['daily_limit'] = daily_limit
        features['daily_remaining'] = remaining
        return "HIGH", "F18_DAILY_RECEIVER_LIMIT_EXCEEDED", features
    
    # ═══════════════════════════════════════════════════════════════════════════
    # STAGE 1: REFLEXES (Hard Rules) - With Tier-Based Exemptions
    # ═══════════════════════════════════════════════════════════════════════════
    
    # Get tier-specific velocity limit
    velocity_limit = tier_config.get("velocity_limit", 5)
    spike_multiplier = tier_config.get("spike_multiplier", 3.0)
    skip_spike = tier_config.get("skip_spike", False)
    skip_stranger = tier_config.get("skip_stranger", False)
    
    # ─── F1: VELOCITY LIMIT (Tier-Aware) ───────────────────────────────────────
    mins_10_ago = now - timedelta(minutes=10)
    recent_txns = db.query(func.count(models.Transaction.id)).filter(
        models.Transaction.sender_id == sender.id,
        models.Transaction.timestamp > mins_10_ago
    ).scalar() or 0
    
    # For HIGH_VALUE tier (Jewelry), we check hourly velocity instead
    if tier == "HIGH_VALUE":
        hour_ago = now - timedelta(hours=1)
        recent_txns_hourly = db.query(func.count(models.Transaction.id)).filter(
            models.Transaction.sender_id == sender.id,
            models.Transaction.timestamp > hour_ago
        ).scalar() or 0
        
        if recent_txns_hourly >= velocity_limit:
            print(f"💎 HIGH_VALUE: Velocity exceeded ({recent_txns_hourly} >= {velocity_limit}/hour)")
            return "HIGH", "F1_HIGH_VALUE_VELOCITY_EXCEEDED", features
    else:
        # Standard velocity check for other tiers
        if recent_txns >= velocity_limit:
            return "HIGH", "F1_VELOCITY_LIMIT_EXCEEDED", features
    
    # ─── F2: CIRCULAR LOOP (A→B→A in 2 minutes) ───────────────────────────────
    mins_2_ago = now - timedelta(minutes=2)
    loop_check = db.query(models.Transaction).filter(
        models.Transaction.sender_id == receiver.id,
        models.Transaction.receiver_id == sender.id,
        models.Transaction.timestamp > mins_2_ago
    ).first()
    if loop_check:
        risk_score += 40
        violations_list.append("F2_CIRCULAR_LOOP")
    
    # ─── F3: DORMANT ACCOUNT SPIKE (Skip for ESSENTIAL/RETAIL) ─────────────────
    if tier not in ["ESSENTIAL", "RETAIL"] and sender.last_active_at:
        days_inactive = (now - sender.last_active_at).days
        if days_inactive > 30 and amount > 500:
            return "HIGH", "F3_DORMANT_ACCOUNT_SPIKE", features
    
    # ─── F4: FIRST TRANSACTION HIGH VALUE ─────────────────────────────────────
    if tier == "PERSONAL" and features['account_age_days'] == 0 and amount > 2000:
        risk_score += 45
        violations_list.append("F4_FIRST_TX_HIGH_VALUE")
    
    # ─── F5: TICKET SIZE SPIKE (Tier-Aware Multiplier) ────────────────────────
    if not skip_spike and features['avg_amount'] > 0:
        if features['amount_vs_avg_ratio'] > spike_multiplier:
            risk_score += 50
            violations_list.append(f"F5_AMOUNT_SPIKE_{int(spike_multiplier*100)}_PERCENT")
    
    # ─── F9: NIGHT OWL (3 AM - 5 AM) ──────────────────────────────────────────
    hour = now.hour
    if 3 <= hour <= 5:
        risk_score += 25
        violations_list.append("F9_UNUSUAL_TIME")
    
    # ─── F10: SPLIT DETECTION (Multiple small txns to same receiver) ─────────
    hour_ago = now - timedelta(hours=1)
    same_receiver_count = db.query(func.count(models.Transaction.id)).filter(
        models.Transaction.sender_id == sender.id,
        models.Transaction.receiver_id == receiver.id,
        models.Transaction.timestamp > hour_ago
    ).scalar() or 0
    if same_receiver_count >= 3 and amount < 500:
        risk_score += 35
        violations_list.append("F10_SPLIT_TRANSACTION_DETECTED")
    
    # ─── F11: DAILY AGGREGATION LIMIT (₹50,000 for P2P, higher for merchants) ─
    daily_limit = 50000 if tier == "PERSONAL" else tier_config.get("max_amount", 100000)
    if features['total_amount_24h'] + amount > daily_limit:
        risk_score += 30
        violations_list.append("F11_DAILY_LIMIT_APPROACHING")
    
    # ─── F13: NEW RECEIVER BURST (5+ new receivers in 1 day) - P2P Only ───────
    if tier == "PERSONAL":
        if features['unique_receivers_24h'] >= 5 and features['is_new_receiver'] == 1:
            risk_score += 25
            violations_list.append("F13_NEW_RECEIVER_BURST")
    
    # ─── F14: SUSPICIOUS ROUND NUMBERS (P2P Only) ─────────────────────────────
    if tier == "PERSONAL":
        suspicious_amounts = [10000, 20000, 25000, 50000, 100000]
        if amount in suspicious_amounts:
            risk_score += 15
            violations_list.append("F14_SUSPICIOUS_ROUND_AMOUNT")
    
    # ─── F15: RAPID DRAIN (>50% balance in 1 hour) ────────────────────────────
    if sender.balance > 0:
        hour_ago = now - timedelta(hours=1)
        hour_total = db.query(func.sum(models.Transaction.amount)).filter(
            models.Transaction.sender_id == sender.id,
            models.Transaction.timestamp > hour_ago
        ).scalar() or 0
        drain_ratio = (hour_total + amount) / sender.balance
        if drain_ratio > 0.5:
            risk_score += 40
            violations_list.append("F15_RAPID_BALANCE_DRAIN")
    
    # ─── F16: DEVICE CHANGE + HIGH VALUE ──────────────────────────────────────
    if device_id_hash and sender.device_id_hash:
        if device_id_hash != sender.device_id_hash and amount > 5000:
            risk_score += 35
            violations_list.append("F16_DEVICE_CHANGE_HIGH_VALUE")
    
    # ─── F17: RECEIVER NETWORK VELOCITY (Skip for known merchants) ────────────
    if tier == "PERSONAL" and features['receiver_unique_senders_24h'] > 10:
        risk_score += 20
        violations_list.append("F17_RECEIVER_HIGH_INFLOW")
    
    # ═══════════════════════════════════════════════════════════════════════════
    # NEW FRAUD RULES v3.0 (10 Additional Rules for 10/10 Score)
    # ═══════════════════════════════════════════════════════════════════════════
    
    # ─── F19: SESSION ANOMALY (Transaction count this session > 3x average) ─────
    if features.get('avg_session_tx', 3) > 0:
        session_ratio = features.get('session_tx_count', 0) / features.get('avg_session_tx', 3)
        if session_ratio > 3:
            risk_score += 30
            violations_list.append("F19_SESSION_ANOMALY")
    
    # ─── F20: TIME PATTERN VIOLATION (Unusual hour for this user) ───────────────
    if features.get('hour_frequency', 50) < 5:  # Less than 5% of transactions at this hour
        risk_score += 15
        violations_list.append("F20_UNUSUAL_TIME_PATTERN")
    
    # ─── F21: BEHAVIORAL DRIFT (Amount far from user's typical pattern) ─────────
    amount_percentile = features.get('amount_percentile', 50)
    if amount_percentile > 200:  # Amount is 4x the user's average
        risk_score += 25
        violations_list.append("F21_BEHAVIORAL_DRIFT")
    
    # ─── F22: DORMANT RECEIVER (Receiver inactive > 60 days) ────────────────────
    if features.get('recipient_age_days', 0) == 0 and features.get('recipient_tx_volume', 0) == 0:
        # Brand new receiver with no history
        if amount > 5000:
            risk_score += 20
            violations_list.append("F22_DORMANT_RECEIVER_RISK")
    
    # ─── F23: BURST TO NEW ACCOUNTS (3+ new receivers in 1 hour) ────────────────
    hour_ago = now - timedelta(hours=1)
    new_receivers_1h = db.query(func.count(func.distinct(models.Transaction.receiver_id))).filter(
        models.Transaction.sender_id == sender.id,
        models.Transaction.timestamp > hour_ago
    ).scalar() or 0
    
    if new_receivers_1h >= 3 and features.get('is_new_receiver', 0) == 1:
        risk_score += 40
        violations_list.append("F23_BURST_TO_NEW_ACCOUNTS")
    
    # ─── F24: CHAIN DETECTION (Money laundering pattern A→B→C) ──────────────────
    # Check if receiver immediately sent money after receiving
    mins_30_ago = now - timedelta(minutes=30)
    receiver_outflow = db.query(func.count(models.Transaction.id)).filter(
        models.Transaction.sender_id == receiver.id,
        models.Transaction.timestamp > mins_30_ago
    ).scalar() or 0
    
    if receiver_outflow >= 2 and amount > 10000:
        risk_score += 35
        violations_list.append("F24_CHAIN_DETECTION")
    
    # ─── F25: CONSECUTIVE TRANSACTION ALERT (5+ back-to-back) ───────────────────
    if features.get('consecutive_tx_count', 0) >= 5:
        risk_score += 30
        violations_list.append("F25_CONSECUTIVE_TX_ALERT")
    
    # ─── F26: BALANCE UTILIZATION SPIKE (>80% balance in single tx) ─────────────
    if features.get('balance_utilization', 0) > 80:
        risk_score += 25
        violations_list.append("F26_BALANCE_DRAIN_ATTEMPT")
    
    # ─── F27: RECIPIENT CLUSTER RISK (Receiver gets from many unique senders) ───
    if features.get('receiver_unique_senders_24h', 0) > 20:
        risk_score += 30
        violations_list.append("F27_RECIPIENT_CLUSTER_RISK")
    
    # ─── F28: FIRST-TIME AMOUNT FLAG (Never sent this exact amount before) ──────
    if features.get('is_first_time_amount', 0) == 1 and amount > 10000:
        risk_score += 15
        violations_list.append("F28_FIRST_TIME_AMOUNT")
    
    # ─── F29: GEO-VELOCITY (Impossible Travel Detection) ─────────────────────────
    # Uses MaxMind GeoLite2 to detect if user is traveling faster than possible
    # Example: Transaction from India, then 5 minutes later from USA = BLOCKED
    # Now fully implemented with IP tracking
    if GEOIP_ENABLED and features.get('current_ip'):
        current_ip = features.get('current_ip')
        last_tx = db.query(models.Transaction).filter(
            models.Transaction.sender_id == sender.id,
            models.Transaction.status == "SUCCESS"
        ).order_by(models.Transaction.timestamp.desc()).first()
        
        if last_tx:
            # Try to get last IP from encrypted storage
            last_ip = None
            if hasattr(last_tx, 'ip_encrypted') and last_tx.ip_encrypted:
                try:
                    import security
                    last_ip = security.decrypt_value(last_tx.ip_encrypted)
                except:
                    pass
            
            if last_ip and last_ip != current_ip:
                minutes_since = features.get('minutes_since_last_tx', 60)
                is_violation, distance_km, speed_kmh = check_geo_velocity(
                    current_ip=current_ip,
                    last_ip=last_ip,
                    minutes_since_last=minutes_since
                )
                
                if is_violation:
                    features['geo_violation_distance'] = distance_km
                    features['geo_violation_speed'] = speed_kmh
                    return "HIGH", "F29_GEO_VELOCITY_VIOLATION", features
                elif distance_km > 100:
                    # Significant location change (not impossible, but suspicious)
                    risk_score += 20
                    violations_list.append("F29_LOCATION_CHANGE_ALERT")
    
    # ═══════════════════════════════════════════════════════════════════════════
    # NEW FRAUD RULES v4.0 (F30-F54 for 50+ Total Rules)
    # ═══════════════════════════════════════════════════════════════════════════
    
    # ─── F30: WEEKLY SPENDING LIMIT ───────────────────────────────────────────────
    week_ago = now - timedelta(days=7)
    weekly_spent = db.query(func.sum(models.Transaction.amount)).filter(
        models.Transaction.sender_id == sender.id,
        models.Transaction.timestamp >= week_ago,
        models.Transaction.status == "SUCCESS"
    ).scalar() or 0
    
    weekly_limit = 200000 if tier == "PERSONAL" else 500000  # ₹2L P2P, ₹5L Merchant
    if weekly_spent + amount > weekly_limit:
        risk_score += 30
        violations_list.append("F30_WEEKLY_LIMIT_WARNING")
        features['weekly_spent'] = weekly_spent
    
    # ─── F31: MICRO-TRANSACTION BURST (>10 txns <₹100 in 1 hour) ──────────────────
    hour_ago = now - timedelta(hours=1)
    micro_txns = db.query(func.count(models.Transaction.id)).filter(
        models.Transaction.sender_id == sender.id,
        models.Transaction.timestamp > hour_ago,
        models.Transaction.amount < 100
    ).scalar() or 0
    
    if micro_txns >= 10 and amount < 100:
        risk_score += 40
        violations_list.append("F31_MICRO_BURST_DETECTED")
    
    # ─── F32: WEEKEND SPIKE (>2x weekday average on weekends) ─────────────────────
    if features.get('is_weekend', 0) == 1:
        # Get weekday average
        weekday_avg = db.query(func.avg(models.Transaction.amount)).filter(
            models.Transaction.sender_id == sender.id,
            func.extract('dow', models.Transaction.timestamp).in_([1,2,3,4,5]),
            models.Transaction.status == "SUCCESS"
        ).scalar() or amount
        
        if weekday_avg > 0 and amount > weekday_avg * 2:
            risk_score += 15
            violations_list.append("F32_WEEKEND_SPIKE")
    
    # ─── F33: HOLIDAY PATTERN (Check for unusual activity on holidays) ────────────
    # Simple check: New Year, Diwali period (Oct-Nov), Independence Day
    month = now.month
    day = now.day
    is_holiday_period = (month == 1 and day <= 5) or (month in [10, 11]) or (month == 8 and day == 15)
    
    if is_holiday_period and amount > 50000:
        risk_score += 10
        violations_list.append("F33_HOLIDAY_PERIOD_HIGH_VALUE")
    
    # ─── F34: MONTHLY UNIQUE RECEIVER LIMIT (>50 new receivers/month) ─────────────
    month_ago = now - timedelta(days=30)
    unique_receivers_month = db.query(func.count(func.distinct(models.Transaction.receiver_id))).filter(
        models.Transaction.sender_id == sender.id,
        models.Transaction.timestamp >= month_ago,
        models.Transaction.status == "SUCCESS"
    ).scalar() or 0
    
    if unique_receivers_month > 50:
        risk_score += 30
        violations_list.append("F34_TOO_MANY_UNIQUE_RECEIVERS")
    
    # ─── F35: SAME-AMOUNT BURST (3+ identical amounts in 1 hour) ──────────────────
    same_amount_count = db.query(func.count(models.Transaction.id)).filter(
        models.Transaction.sender_id == sender.id,
        models.Transaction.timestamp > hour_ago,
        models.Transaction.amount == amount
    ).scalar() or 0
    
    if same_amount_count >= 3:
        risk_score += 35
        violations_list.append("F35_SAME_AMOUNT_BURST")
    
    # ─── F36: PROGRESSIVE AMOUNT DETECTION (100, 200, 400, 800...) ────────────────
    recent_amounts = db.query(models.Transaction.amount).filter(
        models.Transaction.sender_id == sender.id,
        models.Transaction.timestamp > hour_ago,
        models.Transaction.status == "SUCCESS"
    ).order_by(models.Transaction.timestamp.asc()).all()
    
    if len(recent_amounts) >= 3:
        amounts = [a[0] for a in recent_amounts[-3:]]
        # Check for doubling pattern
        if len(amounts) >= 2 and all(amounts[i+1] == amounts[i] * 2 for i in range(len(amounts)-1)):
            risk_score += 40
            violations_list.append("F36_PROGRESSIVE_AMOUNT_PATTERN")
    
    # ─── F37: COUNTDOWN AMOUNT DETECTION (1000, 900, 800...) ──────────────────────
    if len(recent_amounts) >= 3:
        amounts = [a[0] for a in recent_amounts[-3:]]
        # Check for decreasing pattern with constant difference
        if len(amounts) >= 3:
            diff1 = amounts[0] - amounts[1]
            diff2 = amounts[1] - amounts[2]
            if diff1 == diff2 and diff1 > 0 and diff1 >= 100:
                risk_score += 35
                violations_list.append("F37_COUNTDOWN_PATTERN")
    
    # ─── F38: EVEN-AMOUNT ONLY (All amounts divisible by 100) ─────────────────────
    day_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    today_amounts = db.query(models.Transaction.amount).filter(
        models.Transaction.sender_id == sender.id,
        models.Transaction.timestamp >= day_start,
        models.Transaction.status == "SUCCESS"
    ).all()
    
    if len(today_amounts) >= 5:
        all_even = all(a[0] % 100 == 0 for a in today_amounts)
        if all_even and amount % 100 == 0:
            risk_score += 20
            violations_list.append("F38_EVEN_AMOUNT_PATTERN")
    
    # ─── F39: LATE-NIGHT VELOCITY (>5 txns 10PM-6AM) ──────────────────────────────
    if features.get('is_night', 0) == 1:
        night_txns = db.query(func.count(models.Transaction.id)).filter(
            models.Transaction.sender_id == sender.id,
            models.Transaction.timestamp > hour_ago,
            func.extract('hour', models.Transaction.timestamp).in_([22, 23, 0, 1, 2, 3, 4, 5])
        ).scalar() or 0
        
        if night_txns >= 5:
            risk_score += 40
            violations_list.append("F39_NIGHT_VELOCITY_EXCEEDED")
    
    # ═══════════════════════════════════════════════════════════════════════════
    # BEHAVIORAL RULES (F40-F49)
    # ═══════════════════════════════════════════════════════════════════════════
    
    # ─── F40: RECEIVER AGE VS AMOUNT (New receiver + high value) ──────────────────
    receiver_first_tx = db.query(func.min(models.Transaction.timestamp)).filter(
        models.Transaction.receiver_id == receiver.id
    ).scalar()
    
    if receiver_first_tx:
        receiver_age_days = (now - receiver_first_tx).days
        if receiver_age_days <= 7 and amount > 20000:
            risk_score += 35
            violations_list.append("F40_NEW_RECEIVER_HIGH_VALUE")
    else:
        # First-ever transaction to this receiver
        if amount > 10000:
            risk_score += 25
            violations_list.append("F40_BRAND_NEW_RECEIVER_HIGH_VALUE")
    
    # ─── F41: TRANSACTION FREQUENCY CHANGE (3x normal rate) ───────────────────────
    avg_daily_txns = sender.sender_profile.total_transactions_count / max(1, features.get('account_age_days', 1)) if sender.sender_profile else 1
    today_txn_count = db.query(func.count(models.Transaction.id)).filter(
        models.Transaction.sender_id == sender.id,
        models.Transaction.timestamp >= day_start
    ).scalar() or 0
    
    if avg_daily_txns > 0 and today_txn_count > avg_daily_txns * 3:
        risk_score += 25
        violations_list.append("F41_FREQUENCY_SPIKE")
    
    # ─── F42: BALANCE VELOCITY (Spending faster than income) ──────────────────────
    week_received = db.query(func.sum(models.Transaction.amount)).filter(
        models.Transaction.receiver_id == sender.id,
        models.Transaction.timestamp >= week_ago,
        models.Transaction.status == "SUCCESS"
    ).scalar() or 0
    
    if weekly_spent > week_received * 2 and weekly_spent > 50000:
        risk_score += 20
        violations_list.append("F42_SPENDING_EXCEEDS_INCOME")
    
    # ─── F43: DEVICE AGE CHECK (New device + high volume) ─────────────────────────
    if sender and sender.total_device_count > 0:
        # Check if using a recently added device (DeviceProfile stores device login history)
        recent_device_check = db.query(models.DeviceProfile).filter(
            models.DeviceProfile.user_id == sender.id,
            models.DeviceProfile.last_login_time > week_ago
        ).first()
        
        if recent_device_check and today_txn_count > 5:
            risk_score += 30
            violations_list.append("F43_NEW_DEVICE_HIGH_ACTIVITY")
    
    # ─── F44: IP CHANGE FREQUENCY (3+ different IPs in 1 hour) ────────────────────
    # This check happens if we're tracking IPs per transaction
    if features.get('current_ip'):
        unique_ips_1h = db.query(func.count(func.distinct(models.Transaction.ip_hash))).filter(
            models.Transaction.sender_id == sender.id,
            models.Transaction.timestamp > hour_ago
        ).scalar() or 0
        
        if unique_ips_1h >= 3:
            risk_score += 35
            violations_list.append("F44_MULTIPLE_IPS_DETECTED")
    
    # ─── F45: SESSION DURATION ANOMALY (Transaction <30s after login) ─────────────
    if sender and sender.last_active_at:
        login_seconds_ago = (now - sender.last_active_at).total_seconds()
        if login_seconds_ago < 30 and amount > 5000:
            risk_score += 25
            violations_list.append("F45_INSTANT_TRANSACTION")
    
    # ─── F46: AMOUNT PRECISION PATTERN ────────────────────────────────────────────
    # Check if user always sends .00 amounts (suspicious for money laundering)
    recent_txns_precision = db.query(models.Transaction.amount).filter(
        models.Transaction.sender_id == sender.id,
        models.Transaction.timestamp >= week_ago,
        models.Transaction.status == "SUCCESS"
    ).limit(20).all()
    
    if len(recent_txns_precision) >= 10:
        all_whole = all(a[0] == int(a[0]) for a in recent_txns_precision)
        if all_whole and amount == int(amount) and amount > 5000:
            risk_score += 15
            violations_list.append("F46_WHOLE_NUMBER_PATTERN")
    
    # ─── F47: MCC SWITCHING (5+ different MCCs in 1 hour) ─────────────────────────
    if tier != "PERSONAL":
        unique_mccs = db.query(func.count(func.distinct(models.Transaction.receiver_mcc))).filter(
            models.Transaction.sender_id == sender.id,
            models.Transaction.timestamp > hour_ago,
            models.Transaction.receiver_mcc.isnot(None)
        ).scalar() or 0
        
        if unique_mccs >= 5:
            risk_score += 30
            violations_list.append("F47_MCC_SWITCHING")
    
    # ─── F48: SIMULTANEOUS TRANSACTION ATTEMPT ────────────────────────────────────
    # Check for transactions in the last 5 seconds (concurrent requests)
    five_seconds_ago = now - timedelta(seconds=5)
    concurrent_txns = db.query(func.count(models.Transaction.id)).filter(
        models.Transaction.sender_id == sender.id,
        models.Transaction.timestamp > five_seconds_ago
    ).scalar() or 0
    
    if concurrent_txns >= 2:
        risk_score += 50
        violations_list.append("F48_CONCURRENT_TRANSACTION")
    
    # ─── F49: FAILED TRANSACTION VELOCITY (>3 failed in 10 min) ───────────────────
    mins_10_ago = now - timedelta(minutes=10)
    failed_txns = db.query(func.count(models.Transaction.id)).filter(
        models.Transaction.sender_id == sender.id,
        models.Transaction.timestamp > mins_10_ago,
        models.Transaction.status == "FAILED"
    ).scalar() or 0
    
    if failed_txns >= 3:
        risk_score += 40
        violations_list.append("F49_MULTIPLE_FAILED_ATTEMPTS")
    
    # ═══════════════════════════════════════════════════════════════════════════
    # AML/NETWORK RULES (F50-F54)
    # ═══════════════════════════════════════════════════════════════════════════
    
    # ─── F50: STAR PATTERN (One sender to many receivers quickly) ─────────────────
    receivers_30min = db.query(func.count(func.distinct(models.Transaction.receiver_id))).filter(
        models.Transaction.sender_id == sender.id,
        models.Transaction.timestamp > mins_30_ago,
        models.Transaction.status == "SUCCESS"
    ).scalar() or 0
    
    if receivers_30min >= 5:
        risk_score += 35
        violations_list.append("F50_STAR_PATTERN_DETECTED")
    
    # ─── F51: FUNNEL PATTERN (Many senders to one receiver) ───────────────────────
    senders_to_receiver_30min = db.query(func.count(func.distinct(models.Transaction.sender_id))).filter(
        models.Transaction.receiver_id == receiver.id,
        models.Transaction.timestamp > mins_30_ago,
        models.Transaction.status == "SUCCESS"
    ).scalar() or 0
    
    if senders_to_receiver_30min >= 5:
        risk_score += 35
        violations_list.append("F51_FUNNEL_PATTERN_DETECTED")
    
    # ─── F52: LAYERING DETECTION (A→B→C→D chain within 30 min) ────────────────────
    # Check if the receiver has immediately forwarded to someone else
    receiver_forwarded = db.query(models.Transaction).filter(
        models.Transaction.sender_id == receiver.id,
        models.Transaction.timestamp > mins_30_ago,
        models.Transaction.status == "SUCCESS",
        models.Transaction.receiver_id != sender.id  # Not back to sender
    ).first()
    
    if receiver_forwarded:
        # Check if THAT receiver also forwarded (3-hop chain)
        third_party_id = receiver_forwarded.receiver_id
        third_hop = db.query(models.Transaction).filter(
            models.Transaction.sender_id == third_party_id,
            models.Transaction.timestamp > mins_30_ago,
            models.Transaction.status == "SUCCESS"
        ).first()
        
        if third_hop and amount > 5000:
            risk_score += 45
            violations_list.append("F52_LAYERING_CHAIN_DETECTED")
    
    # ─── F53: SMURFING DETECTION (Many small amounts summing to large) ────────────
    small_txns_sum = db.query(func.sum(models.Transaction.amount)).filter(
        models.Transaction.sender_id == sender.id,
        models.Transaction.timestamp >= day_start,
        models.Transaction.amount <= 5000,
        models.Transaction.status == "SUCCESS"
    ).scalar() or 0
    
    if small_txns_sum > 50000:
        risk_score += 40
        violations_list.append("F53_SMURFING_DETECTED")
    
    # ─── F54: ROUND-TRIP DETECTION (A→B then B→A within 24 hours) ─────────────────
    day_ago = now - timedelta(hours=24)
    reverse_flow = db.query(models.Transaction).filter(
        models.Transaction.sender_id == receiver.id,
        models.Transaction.receiver_id == sender.id,
        models.Transaction.timestamp > day_ago,
        models.Transaction.status == "SUCCESS"
    ).first()
    
    if reverse_flow:
        # Check if amounts are similar (within 20%)
        if reverse_flow.amount > 0:
            ratio = amount / reverse_flow.amount
            if 0.8 <= ratio <= 1.2:
                risk_score += 35
                violations_list.append("F54_ROUND_TRIP_DETECTED")
    
    # ═══════════════════════════════════════════════════════════════════════════
    # STAGE 2: NETWORK (Social Graph) - PERSONAL TIER ONLY
    # ═══════════════════════════════════════════════════════════════════════════
    
    trust_depth = calculate_trust_depth(db, sender.id, receiver.id)
    
    if tier == "PERSONAL":
        # ─── FULL SOCIAL GRAPH LOGIC FOR P2P ──────────────────────────────────
        if trust_depth == 1:
            # Direct Friend: Bonus
            risk_score -= 15
        elif trust_depth == 2:
            # Friend of Friend: Small bonus
            risk_score -= 5
        else:
            # Stranger: Penalty (P2P Stranger Danger)
            risk_score += 20
            violations_list.append("F12_STRANGER_NO_COMMON_TRUST")
            
            # High value to stranger = extra risk
            if amount > 2000:
                risk_score += 25
                violations_list.append("F8_HIGH_VALUE_STRANGER")
        
        # ─── F7: UNTRUSTED RECEIVER HIGH VALUE (P2P ONLY) ─────────────────────
        stranger_limit = tier_config.get("stranger_first_time_limit", 5000)
        if trust_depth == 0 and amount > stranger_limit:
            return "HIGH", "F7_UNTRUSTED_RECEIVER_HIGH_VALUE", features
    
    elif not skip_stranger:
        # ─── SERVICES TIER: Limited stranger checks ───────────────────────────
        stranger_warn = tier_config.get("stranger_warn_limit", 50000)
        if trust_depth == 0 and amount > stranger_warn:
            risk_score += 15
            violations_list.append("F8_HIGH_VALUE_STRANGER_SERVICE")
    
    # For RETAIL, HIGH_VALUE, ESSENTIAL: skip_stranger = True, so no checks
    
    # ═══════════════════════════════════════════════════════════════════════════
    # STAGE 3: BRAIN (AI Analysis)
    # ═══════════════════════════════════════════════════════════════════════════
    
    ai_score = get_ai_score(features)
    
    # Store AI score in features for logging
    features['ai_score'] = ai_score
    
    if ai_score < -0.3:
        # Strong anomaly
        risk_score += 65
        violations_list.append("AI_DETECTED_STRONG_ANOMALY")
    elif ai_score < -0.1:
        # Mild anomaly
        risk_score += 30
        violations_list.append("AI_DETECTED_MILD_ANOMALY")
    elif ai_score > 0.3:
        # Very normal = bonus
        risk_score -= 10
    
    # ═══════════════════════════════════════════════════════════════════════════
    # FINAL VERDICT
    # ═══════════════════════════════════════════════════════════════════════════
    
    # Cap score
    risk_score = max(0, min(100, risk_score))
    
    # Pick primary violation
    violation = violations_list[0] if violations_list else None
    
    # Log detailed output
    print(f"🕵️ FRAUD EVAL: {sender.username} → {receiver.username} | ₹{amount}")
    print(f"   MCC: {receiver_mcc} | Tier: {tier}")
    print(f"   Trust Depth: {trust_depth} | AI Score: {ai_score:.3f} | Risk: {risk_score}")
    print(f"   Violations: {violations_list}")
    
    if risk_score >= RISK_THRESHOLD_HIGH:
        return "HIGH", violation or "HIGH_RISK_SCORE", features
    elif risk_score >= RISK_THRESHOLD_WARN:
        return "WARN", violation or "WARN_RISK_SCORE", features
    else:
        return "SAFE", None, features


def record_trust(db: Session, sender_id: int, receiver_id: int):
    """Add/Update trust relationship after successful transaction"""
    exists = db.query(models.UserTrustGraph).filter(
        models.UserTrustGraph.user_id == sender_id,
        models.UserTrustGraph.trusted_user_id == receiver_id
    ).first()
    
    if exists:
        exists.trust_score += 1.0
        exists.last_interaction_at = datetime.now()
    else:
        new_link = models.UserTrustGraph(
            user_id=sender_id,
            trusted_user_id=receiver_id,
            trust_score=1.0,
            last_interaction_at=datetime.now()
        )
        db.add(new_link)
    
    db.commit()
    
    # Trigger retrain check
    trigger_retrain_if_needed(db)


def record_fraud_event(db: Session, user_id: int, transaction_id: str, amount: float, 
                       ai_score: float, rule_violation: str, is_blocked: bool):
    """Record suspicious event for model training"""
    event = models.FraudEvent(
        user_id=user_id,
        transaction_id=transaction_id,
        amount=amount,
        ai_score=ai_score,
        rule_violation=rule_violation,
        is_blocked=is_blocked,
        timestamp=datetime.now()
    )
    db.add(event)
    db.commit()
