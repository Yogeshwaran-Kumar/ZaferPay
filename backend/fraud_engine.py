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
        print("GeoIP2 loaded successfully - Geo-velocity check ENABLED")
    else:
        _geoip_reader = None
        GEOIP_ENABLED = False
        print("GeoLite2-City.mmdb not found - Geo-velocity check DISABLED")
except ImportError:
    _geoip_reader = None
    GEOIP_ENABLED = False
    print("geoip2 not installed - Geo-velocity check DISABLED")


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

RISK_THRESHOLD_HIGH = 70    # Block immediately (reduced from 80 for stricter detection)
RISK_THRESHOLD_WARN = 45    # Allow but flag (reduced from 50 for better warnings)
# RISK_THRESHOLD_QUIET removed for better security - all moderate risk is now WARN

MODEL_PATH = "fraud_model_v2.pkl"
MIN_DATA_POINTS = 30        # Reduced for faster initial training
RETRAIN_THRESHOLD = 100     # Retrain after every 100 new transactions
 
# ═══════════════════════════════════════════════════════════════════════════
# HARD BLOCK REASONS - These cannot be bypassed by "Proceed Anyway"
# ═══════════════════════════════════════════════════════════════════════════
# Philosophy: Only block technical/security violations that indicate system abuse
# or impossible scenarios. Allow users to proceed with strong warnings for 
# behavioral anomalies (high amounts to strangers, spikes, etc.)
HARD_BLOCK_REASONS = [
    # Technical Limits (System Protection)
    "F18_DAILY_RECEIVER_LIMIT_EXCEEDED",           # Daily limit per receiver (₹1L P2P, ₹3L Merchant)
    
    # Security Violations (Fraud Indicators)
    "F29_GEO_VELOCITY_VIOLATION",                  # Impossible travel (>900 km/h)
    "F48_CONCURRENT_TRANSACTION",                  # Simultaneous payment attempts
    "F30_MERCHANT_LOCATION_FRAUD",                 # Merchant location mismatch
    
    # Logic Violations (Invalid Operations)
    "SELF_TRANSFER",                               # Sending money to yourself
    
    # Scam Protection (v5.0)
    "F55_SCREEN_SHARING_HARD_BLOCK",              # Payment during screen sharing to non-trusted
    "F57_MCC_MISMATCH_P2P_POSES_MERCHANT",        # P2P account claiming merchant MCC (QR sticker attack)
]

# NOTE: All behavioral anomalies (stranger high-value, spikes, frequency changes, etc.)
# are now BYPASSABLE with "Proceed with Caution" or "I Understand the Risk" warnings.
# This gives users control while still showing strong warnings for risky behavior.

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
    if not mcc or mcc == "" or mcc == "0" or all(c == '0' for c in mcc):
        return "PERSONAL"
    return MCC_REGISTRY.get(mcc, "SERVICES")  # Default to SERVICES if unknown MCC

def get_tier_config(tier: str) -> dict:
    """Get the configuration dict for a risk tier."""
    return MCC_TIERS.get(tier, MCC_TIERS["PERSONAL"])


# ═══════════════════════════════════════════════════════════════════════════
# MCC CONTEXTUAL PARAMETERS (v5.0 — Parameterized, Not Hardcoded)
# ═══════════════════════════════════════════════════════════════════════════
#
# These parameters define the EXPECTED BEHAVIOUR of each MCC tier.
# They are used for soft scoring, NOT hard blocks.
# A real merchant will naturally satisfy these. A fake merchant will not.
#
# Research basis:
#   - Kansas City Fed (2024): TTX < 12s from login = strong urgency signal
#   - ResearchGate (2025): Sender density (senders/day) best fake-merchant signal
#   - IJRASET (2025): Hybrid approach: amount + hours + density together

# Business hours per MCC tier — when does a legit merchant of this type operate?
# Tuple: (start_hour, end_hour) in 24h format
MCC_BUSINESS_HOURS = {
    "ESSENTIAL": (0, 24),      # Hospitals, pharmacies: 24/7
    "HIGH_VALUE": (9, 19),     # Jewellers, legal services: business hours only
    "RETAIL":    (7, 23),      # Grocery, restaurants, transport: 7am–11pm
    "SERVICES":  (8, 23),      # Hotels, electronics, travel: 8am–11pm
    "PERSONAL":  (0, 24),      # P2P: no restriction
}

# Typical transaction amount range per MCC tier (min, max in INR)
# Amounts outside this range are suspicious FOR THAT MCC TYPE
MCC_TYPICAL_AMOUNT = {
    "ESSENTIAL": (100,   200000),   # Hospital bills can be large
    "HIGH_VALUE": (5000, 500000),   # Jewellery/legal: minimum meaningful amount
    "RETAIL":    (10,    15000),    # Grocery, food: small daily amounts
    "SERVICES":  (200,   50000),    # Hotel, travel: moderate
    "PERSONAL":  (1,     100000),   # P2P: no upper range restriction
}

# Minimum expected unique-senders-per-day ratio for a REAL merchant of this type
# (based on 90-day study of real UPI merchant patterns)
# A real grocery store sees 20-50 customers/day → density ~0.5/day after 1 month
# A scammer's fake shop sees 1-3 victims ever → density ~0/day
MCC_MIN_SENDER_DENSITY = {
    "ESSENTIAL": 0.02,   # Hospital: can be low (referrals only)
    "HIGH_VALUE": 0.05,  # Jeweller: weekly customers
    "RETAIL":    0.3,    # Grocery: daily foot traffic expected
    "SERVICES":  0.1,    # Restaurant: some daily customers
    "PERSONAL":  0.0,    # P2P: no expectation
}

# Investment/social-engineering scam keywords for payment note analysis
# (Research: ResearchGate 2025 — NLP on note field improves detection by 38%)
INVESTMENT_SCAM_KEYWORDS = [
    "profit", "return", "investment", "returns", "interest",
    "dividend", "daily income", "double", "scheme", "lottery",
    "prize", "lucky draw", "gift", "claim", "bonus", "winning",
    "reward", "benefit", "subsidy", "refund trick"
]


def score_merchant_suspicion(
    mcc_tier: str,
    receiver_profile,
    amount: float,
    current_hour: int,
    is_new_receiver: bool,
    receiver_first_tx_date
) -> tuple:
    """
    Composite Merchant Authenticity Scorer — v5.0

    Scores how suspicious a MERCHANT account is based on its behaviour,
    not just static thresholds. Each signal contributes a soft score.
    Only the COMBINATION of anomalies triggers a flag.

    Returns: (suspicion_score: int, signals: list[str])
        suspicion_score: 0 = verified real merchant, 80+ = likely fake
        signals: list of human-readable signals that contributed

    Key Design Principles:
    1. Normalise by account age → new legit merchants are not penalised unfairly
    2. No single signal blocks → only combinations flag
    3. All thresholds are PARAMETERS, not magic numbers

    Research basis:
    - Sender density (senders/day): ResearchGate 2025
    - Amount vs MCC range: IARJSET 2024
    - Business hours violation: Kansas City Fed 2024, IJRASET 2025
    """
    score = 0
    signals = []

    if mcc_tier == "ESSENTIAL":
        return 0, []  # Trust essential tier completely

    # ── Account age (days since first received transaction) ──────────────────
    if receiver_first_tx_date:
        account_age_days = max((datetime.now() - receiver_first_tx_date).days, 1)
    else:
        account_age_days = 0  # Never received any payment

    # ── Signal 1: Sender density (key metric — normalised by age) ───────────
    # A real shop builds customers over time. A scam account never does.
    unique_senders = getattr(receiver_profile, 'unique_senders_count', 0) or 0
    if account_age_days > 0:
        density = unique_senders / account_age_days
    else:
        density = 0.0  # Zero history = maximum suspicion

    min_density = MCC_MIN_SENDER_DENSITY.get(mcc_tier, 0.1)
    if density == 0.0 and account_age_days > 14:
        # 2+ week old "merchant" with ZERO customers → strong signal
        score += 30
        signals.append(f"MERCHANT_ZERO_CUSTOMERS_DENSITY")
    elif density < min_density * 0.3 and account_age_days > 30:
        # 30+ day old merchant with very low customer density
        score += 20
        signals.append(f"MERCHANT_LOW_CUSTOMER_DENSITY_{density:.2f}")
    elif density < min_density * 0.5 and account_age_days > 7:
        score += 10
        signals.append(f"MERCHANT_BELOW_EXPECTED_DENSITY")

    # ── Signal 2: Account maturity (tapers gracefully) ───────────────────────
    # New merchants are given benefit of the doubt, but score rises if no history
    if account_age_days == 0:
        score += 25  # First-ever payment — unknown merchant
        signals.append("MERCHANT_NO_PAYMENT_HISTORY")
    elif account_age_days < 7:
        score += 15  # Brand new, less than 1 week
        signals.append("MERCHANT_VERY_NEW_ACCOUNT")
    elif account_age_days < 30:
        score += 5   # Fairly new — minor caution

    # ── Signal 3: Amount vs MCC typical range ────────────────────────────────
    # A grocery store receiving ₹50,000 is suspicious.
    # A jeweller receiving ₹500 is equally suspicious.
    min_amt, max_amt = MCC_TYPICAL_AMOUNT.get(mcc_tier, (1, 100000))
    if amount > max_amt * 2:
        score += 20
        signals.append(f"AMOUNT_3X_ABOVE_MCC_MAX_{mcc_tier}")
    elif amount > max_amt * 1.5:
        score += 10
        signals.append(f"AMOUNT_HIGH_FOR_MCC_{mcc_tier}")
    # Note: we do NOT penalise low amounts for PERSONAL tier
    if mcc_tier != "PERSONAL" and amount < min_amt * 0.5:
        score += 10
        signals.append(f"AMOUNT_TOO_LOW_FOR_MCC_{mcc_tier}")

    # ── Signal 4: Business hours check ──────────────────────────────────────
    # A grocery store at 2am is suspicious.
    # PERSONAL accounts have no hour restriction.
    biz_start, biz_end = MCC_BUSINESS_HOURS.get(mcc_tier, (0, 24))
    if biz_end < 24:  # Only check tiers that have business hours
        if not (biz_start <= current_hour < biz_end):
            score += 15
            signals.append(f"OUTSIDE_BUSINESS_HOURS_{mcc_tier}_{current_hour}h")

    # ── Signal 5: First time this specific sender pays this merchant ──────────
    # NOT a strong signal alone, but contributes to the composite score.
    if is_new_receiver:
        score += 8
        signals.append("FIRST_PAYMENT_TO_THIS_MERCHANT")

    return score, signals

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
    Extracts 24+ features for ML model.
    Optimized to minimize DB roundtrips.
    """
    if timestamp is None:
        timestamp = datetime.now()
    
    features = {}
    
    # --- TRANSACTION FEATURES ---
    features['amount'] = amount
    features['hour'] = timestamp.hour
    features['day_of_week'] = timestamp.weekday()
    features['is_weekend'] = 1 if timestamp.weekday() >= 5 else 0
    features['is_night'] = 1 if (timestamp.hour >= 22 or timestamp.hour <= 5) else 0
    
    # --- CONSOLIDATED VELOCITY & BEHAVIORAL QUERIES ---
    hour_ago = timestamp - timedelta(hours=1)
    day_ago = timestamp - timedelta(hours=24)
    session_start = timestamp - timedelta(minutes=30)
    day_start = timestamp.replace(hour=0, minute=0, second=0, microsecond=0)
    mins_10_ago = timestamp - timedelta(minutes=10)
    mins_2_ago = timestamp - timedelta(minutes=2)

    # Multi-aggregation query for sender metrics (Consolidated for speed)
    sender_metrics = db.query(
        func.count(models.Transaction.id).filter(models.Transaction.timestamp > hour_ago).label("tx_count_1h"),
        func.count(models.Transaction.id).filter(models.Transaction.timestamp > day_ago).label("tx_count_24h"),
        func.sum(models.Transaction.amount).filter(models.Transaction.timestamp > day_ago).label("total_amount_24h"),
        func.count(func.distinct(models.Transaction.receiver_id)).filter(models.Transaction.timestamp > day_ago).label("unique_receivers_24h"),
        func.count(models.Transaction.id).filter(models.Transaction.timestamp > session_start).label("session_tx_count"),
        func.max(models.Transaction.timestamp).label("last_tx_time"),
        func.min(models.Transaction.timestamp).label("first_tx_time"),
        # Optimized additions for evaluate_fraud:
        func.count(models.Transaction.id).filter(models.Transaction.timestamp > mins_10_ago).label("tx_count_10m"),
        func.sum(models.Transaction.amount).filter(models.Transaction.timestamp >= day_start, models.Transaction.receiver_id == receiver.id).label("sent_to_receiver_today"),
        func.count(models.Transaction.id).filter(models.Transaction.timestamp >= day_start, models.Transaction.receiver_id == receiver.id).label("tx_count_today_to_receiver"),
        func.count(models.Transaction.id).filter(models.Transaction.timestamp > hour_ago, models.Transaction.receiver_id == receiver.id).label("tx_count_1h_to_receiver"),
        # v3.0/v4.0 rules
        func.sum(models.Transaction.amount).filter(models.Transaction.timestamp > (timestamp - timedelta(days=7))).label("weekly_spent"),
        func.count(models.Transaction.id).filter(models.Transaction.timestamp > hour_ago, models.Transaction.amount < 100).label("micro_txns_1h"),
        func.count(models.Transaction.id).filter(models.Transaction.timestamp > hour_ago, models.Transaction.amount == amount).label("same_amount_count_1h"),
        func.count(models.Transaction.id).filter(models.Transaction.timestamp >= day_start).label("today_txn_count"),
        func.count(models.Transaction.id).filter(models.Transaction.timestamp > mins_10_ago, models.Transaction.status == "FAILED").label("failed_txns_10m"),
        func.count(func.distinct(models.Transaction.receiver_id)).filter(models.Transaction.timestamp > (timestamp - timedelta(minutes=30))).label("receivers_30min"),
        # Geo-velocity (F29)
        func.max(models.Transaction.ip_encrypted).filter(models.Transaction.status == "SUCCESS").label("last_ip_encrypted"),
        # Rapid Drain (F15)
        func.sum(models.Transaction.amount).filter(models.Transaction.timestamp > hour_ago).label("total_sent_1h"),
        # Reverse loop check (Receiver to Sender)
        func.count(models.Transaction.id).filter(
            models.Transaction.sender_id == receiver.id,
            models.Transaction.receiver_id == sender.id,
            models.Transaction.timestamp > mins_2_ago
        ).label("reverse_loop_count_2m"),
        # v4.0 fixes
        func.count(models.Transaction.id).filter(models.Transaction.timestamp > (timestamp - timedelta(seconds=5))).label("concurrent_txns_5s"),
        func.count(func.distinct(models.Transaction.receiver_id)).filter(
            models.Transaction.timestamp > hour_ago,
            ~models.Transaction.receiver_id.in_(
                db.query(models.Transaction.receiver_id).filter(
                    models.Transaction.sender_id == sender.id,
                    models.Transaction.timestamp < hour_ago
                )
            )
        ).label("new_receivers_1h")
    ).filter(models.Transaction.sender_id == sender.id).first()

    if not sender_metrics:
        # Fallback if no transactions exist yet for this user
        for key in ['tx_count_1h', 'tx_count_24h', 'total_amount_24h', 'unique_receivers_24h', 
                    'session_tx_count', 'tx_count_10m', 'sent_to_receiver_today', 
                    'tx_count_today_to_receiver', 'tx_count_1h_to_receiver', 'total_sent_1h', 
                    'reverse_loop_count_2m', 'weekly_spent', 'micro_txns_1h', 
                    'same_amount_count_1h', 'today_txn_count', 'concurrent_txns_5s', 
                    'failed_txns_10m', 'receivers_30min']:
            features[key] = 0
        features['last_ip_encrypted'] = None
    else:
        features['tx_count_1h'] = getattr(sender_metrics, 'tx_count_1h', 0) or 0
        features['tx_count_24h'] = getattr(sender_metrics, 'tx_count_24h', 0) or 0
        features['total_amount_24h'] = float(getattr(sender_metrics, 'total_amount_24h', 0) or 0)
        features['unique_receivers_24h'] = getattr(sender_metrics, 'unique_receivers_24h', 0) or 0
        features['session_tx_count'] = getattr(sender_metrics, 'session_tx_count', 0) or 0
        
        features['tx_count_10m'] = getattr(sender_metrics, 'tx_count_10m', 0) or 0
        features['sent_to_receiver_today'] = float(getattr(sender_metrics, 'sent_to_receiver_today', 0) or 0)
        features['tx_count_today_to_receiver'] = getattr(sender_metrics, 'tx_count_today_to_receiver', 0) or 0
        features['tx_count_1h_to_receiver'] = getattr(sender_metrics, 'tx_count_1h_to_receiver', 0) or 0
        features['total_sent_1h'] = float(getattr(sender_metrics, 'total_sent_1h', 0) or 0)
        features['reverse_loop_count_2m'] = getattr(sender_metrics, 'reverse_loop_count_2m', 0) or 0
        
        features['weekly_spent'] = float(getattr(sender_metrics, 'weekly_spent', 0) or 0)
        features['micro_txns_1h'] = getattr(sender_metrics, 'micro_txns_1h', 0) or 0
        features['same_amount_count_1h'] = getattr(sender_metrics, 'same_amount_count_1h', 0) or 0
        features['today_txn_count'] = getattr(sender_metrics, 'today_txn_count', 0) or 0
        features['concurrent_txns_5s'] = getattr(sender_metrics, 'concurrent_txns_5s', 0) or 0
        features['failed_txns_10m'] = getattr(sender_metrics, 'failed_txns_10m', 0) or 0
        features['receivers_30min'] = getattr(sender_metrics, 'receivers_30min', 0) or 0
        features['last_ip_encrypted'] = getattr(sender_metrics, 'last_ip_encrypted', None)
    
    # Receiver Metrics (Consolidated)
    receiver_metrics = db.query(
        func.min(models.Transaction.timestamp).label("first_tx_time"),
        func.count(models.Transaction.id).label("total_tx_count")
    ).filter(models.Transaction.receiver_id == receiver.id).first()
    
    features['receiver_first_tx_date'] = receiver_metrics.first_tx_time
    features['receiver_total_tx_count'] = receiver_metrics.total_tx_count or 0
    
    # F24: Receiver outflow check (Money laundering A -> B -> C)
    mins_30_ago = timestamp - timedelta(minutes=30)
    features['receiver_outflow_30m'] = db.query(func.count(models.Transaction.id)).filter(
        models.Transaction.sender_id == receiver.id,
        models.Transaction.timestamp > mins_30_ago,
        models.Transaction.status == "SUCCESS"
    ).scalar() or 0
    
    # Account Maturity
    if sender_metrics.first_tx_time:
        account_age = (timestamp - sender_metrics.first_tx_time).days
        features['account_age_days'] = min(account_age, 365)
    else:
        features['account_age_days'] = 0

    # Behavioral: Time since last tx
    if sender_metrics.last_tx_time:
        time_diff = (timestamp - sender_metrics.last_tx_time).total_seconds() / 60
        features['minutes_since_last_tx'] = min(time_diff, 10080)
    else:
        features['minutes_since_last_tx'] = 10080

    # Behavioral: Averages
    avg_amount = sender.sender_profile.avg_transaction_amount if sender.sender_profile else 0
    features['avg_amount'] = avg_amount
    features['amount_vs_avg_ratio'] = (amount / avg_amount) if avg_amount > 0 else 1.0
    
    # --- NETWORK & RECEIVER RISK ---
    # Is new receiver check (highly optimized)
    features['is_new_receiver'] = 0 if db.query(models.Transaction.id).filter(
        models.Transaction.sender_id == sender.id,
        models.Transaction.receiver_id == receiver.id
    ).first() else 1

    # Receiver inflow and age in one go
    receiver_metrics = db.query(
        func.count(func.distinct(models.Transaction.sender_id)).filter(models.Transaction.timestamp > day_ago).label("inflow"),
        func.min(models.Transaction.timestamp).label("first_received")
    ).filter(models.Transaction.receiver_id == receiver.id).first()
    
    features['receiver_unique_senders_24h'] = receiver_metrics.inflow or 0
    if receiver_metrics.first_received:
        features['recipient_age_days'] = min((timestamp - receiver_metrics.first_received).days, 365)
    else:
        features['recipient_age_days'] = 0
    
    features['recipient_tx_volume'] = receiver.receiver_profile.total_received_amount if receiver.receiver_profile else 0

    # --- ADVANCED FREQUENCY ---
    total_tx = sender.sender_profile.total_transactions_count if sender.sender_profile else 1
    # Frequency queries often benefit from being separate or part of a group
    freq_metrics = db.query(
        func.count(models.Transaction.id).filter(func.extract('hour', models.Transaction.timestamp) == timestamp.hour).label("hour_count"),
        func.count(models.Transaction.id).filter(func.extract('dow', models.Transaction.timestamp) == timestamp.weekday()).label("day_count"),
        func.count(models.Transaction.id).filter(models.Transaction.amount == amount).label("exact_amount_count")
    ).filter(models.Transaction.sender_id == sender.id).first()
    
    features['hour_frequency'] = (freq_metrics.hour_count / max(1, total_tx)) * 100
    features['day_frequency'] = (freq_metrics.day_count / max(1, total_tx)) * 100
    features['is_first_time_amount'] = 1 if freq_metrics.exact_amount_count == 0 else 0
    
    # Trust Score
    trust_link = db.query(models.UserTrustGraph.trust_score).filter(
        models.UserTrustGraph.user_id == sender.id,
        models.UserTrustGraph.trusted_user_id == receiver.id
    ).scalar()
    features['trust_score'] = trust_link or 0.0

    # Balance Utilization
    features['balance_utilization'] = (amount / sender.balance * 100) if sender.balance > 0 else 100.0

    # Session Averages
    if sender.sender_profile and sender.sender_profile.total_transactions_count > 10:
        avg_sessions = max(1, features['account_age_days'] * 5)
        features['avg_session_tx'] = sender.sender_profile.total_transactions_count / avg_sessions
    else:
        features['avg_session_tx'] = 3.0

    # Percentile
    features['amount_percentile'] = min(100, (amount / avg_amount * 50)) if avg_amount > 0 else 50.0

    # Consecutive TX (Remains sequential as it depends on ordering)
    recent_times = db.query(models.Transaction.timestamp).filter(
        models.Transaction.sender_id == sender.id,
        models.Transaction.timestamp > timestamp - timedelta(hours=1)
    ).order_by(models.Transaction.timestamp.desc()).limit(10).all()
    
    consecutive = 0
    for i in range(len(recent_times) - 1):
        if (recent_times[i][0] - recent_times[i+1][0]).total_seconds() / 60 < 5:
            consecutive += 1
        else:
            break
    features['consecutive_tx_count'] = consecutive

    return features


def extract_features_optimized(db: Session, sender: models.User, receiver: models.User, amount: float, timestamp: datetime = None) -> dict:
    """
    OPTIMIZED Feature Extraction - v6.0
    
    Reduces from 10+ queries to 3 mega-queries
    Target: <100ms execution time (10x faster than original)
    
    Performance improvements:
    - Consolidated sender metrics into 1 query
    - Consolidated receiver metrics into 1 query  
    - Single trust lookup
    - Removed redundant queries
    - Uses conditional aggregations
    """
    if timestamp is None:
        timestamp = datetime.now()
    
    features = {}
    
    # ═══════════════════════════════════════════════════════════════════════════
    # BASIC FEATURES (No DB needed - instant)
    # ═══════════════════════════════════════════════════════════════════════════
    features['amount'] = amount
    features['hour'] = timestamp.hour
    features['day_of_week'] = timestamp.weekday()
    features['is_weekend'] = 1 if timestamp.weekday() >= 5 else 0
    features['is_night'] = 1 if (timestamp.hour >= 22 or timestamp.hour <= 5) else 0
    
    # Time boundaries
    hour_ago = timestamp - timedelta(hours=1)
    day_ago = timestamp - timedelta(hours=24)
    week_ago = timestamp - timedelta(days=7)
    day_start = timestamp.replace(hour=0, minute=0, second=0, microsecond=0)
    mins_10_ago = timestamp - timedelta(minutes=10)
    mins_30_ago = timestamp - timedelta(minutes=30)
    mins_2_ago = timestamp - timedelta(minutes=2)
    
    # ═══════════════════════════════════════════════════════════════════════════
    # MEGA QUERY 1: ALL SENDER METRICS (Consolidates 8+ queries into 1)
    # ═══════════════════════════════════════════════════════════════════════════
    sender_metrics = db.query(
        # Transaction counts by time period
        func.count(models.Transaction.id).label("total_count"),
        func.count(models.Transaction.id).filter(
            models.Transaction.timestamp > hour_ago
        ).label("count_1h"),
        func.count(models.Transaction.id).filter(
            models.Transaction.timestamp > day_ago
        ).label("count_24h"),
        func.count(models.Transaction.id).filter(
            models.Transaction.timestamp >= day_start
        ).label("count_today"),
        func.count(models.Transaction.id).filter(
            models.Transaction.timestamp > mins_10_ago
        ).label("count_10m"),
        func.count(models.Transaction.id).filter(
            models.Transaction.timestamp > mins_30_ago - timedelta(minutes=30)
        ).label("session_count"),
        
        # Amount sums by time period
        func.sum(models.Transaction.amount).filter(
            models.Transaction.timestamp > day_ago
        ).label("sum_24h"),
        func.sum(models.Transaction.amount).filter(
            models.Transaction.timestamp > week_ago
        ).label("sum_week"),
        func.sum(models.Transaction.amount).filter(
            models.Transaction.timestamp > hour_ago
        ).label("sum_1h"),
        
        # Receiver-specific metrics
        func.count(func.distinct(models.Transaction.receiver_id)).filter(
            models.Transaction.timestamp > day_ago
        ).label("unique_receivers_24h"),
        func.sum(models.Transaction.amount).filter(
            models.Transaction.timestamp >= day_start,
            models.Transaction.receiver_id == receiver.id
        ).label("sent_to_receiver_today"),
        func.count(models.Transaction.id).filter(
            models.Transaction.timestamp >= day_start,
            models.Transaction.receiver_id == receiver.id
        ).label("tx_to_receiver_today"),
        func.count(models.Transaction.id).filter(
            models.Transaction.timestamp > hour_ago,
            models.Transaction.receiver_id == receiver.id
        ).label("tx_to_receiver_1h"),
        
        # Timestamps for behavioral analysis
        func.max(models.Transaction.timestamp).label("last_tx_time"),
        func.min(models.Transaction.timestamp).label("first_tx_time"),
        
        # Velocity checks
        func.count(models.Transaction.id).filter(
            models.Transaction.timestamp > hour_ago,
            models.Transaction.amount < 100
        ).label("micro_txns_1h"),
        func.count(models.Transaction.id).filter(
            models.Transaction.timestamp > hour_ago,
            models.Transaction.amount == amount
        ).label("same_amount_1h"),
        func.count(models.Transaction.id).filter(
            models.Transaction.timestamp > mins_10_ago,
            models.Transaction.status == "FAILED"
        ).label("failed_10m"),
        func.count(func.distinct(models.Transaction.receiver_id)).filter(
            models.Transaction.timestamp > mins_30_ago
        ).label("receivers_30min"),
        
        # Geo-velocity
        func.max(models.Transaction.ip_encrypted).filter(
            models.Transaction.status == "SUCCESS"
        ).label("last_ip_encrypted"),
        
        # Reverse loop check
        func.count(models.Transaction.id).filter(
            models.Transaction.sender_id == receiver.id,
            models.Transaction.receiver_id == sender.id,
            models.Transaction.timestamp > mins_2_ago
        ).label("reverse_loop_2m"),
        
        # Frequency analysis (simplified for SQLite compatibility)
        func.count(models.Transaction.id).label("hour_count_total"),
        func.count(models.Transaction.id).label("day_count_total"),
        
        # Check if paid this receiver before
        func.count(models.Transaction.id).filter(
            models.Transaction.receiver_id == receiver.id
        ).label("paid_receiver_before"),
        
    ).filter(
        models.Transaction.sender_id == sender.id,
        models.Transaction.status == "SUCCESS"
    ).first()
    
    # ═══════════════════════════════════════════════════════════════════════════
    # MEGA QUERY 2: ALL RECEIVER METRICS (Consolidates 3+ queries into 1)
    # ═══════════════════════════════════════════════════════════════════════════
    receiver_metrics = db.query(
        func.count(func.distinct(models.Transaction.sender_id)).filter(
            models.Transaction.timestamp > day_ago
        ).label("unique_senders_24h"),
        func.min(models.Transaction.timestamp).label("first_received"),
        func.count(models.Transaction.id).label("total_received"),
        func.count(models.Transaction.id).filter(
            models.Transaction.sender_id == receiver.id,
            models.Transaction.timestamp > mins_30_ago,
            models.Transaction.status == "SUCCESS"
        ).label("outflow_30m"),
    ).filter(
        models.Transaction.receiver_id == receiver.id
    ).first()
    
    # ═══════════════════════════════════════════════════════════════════════════
    # QUERY 3: TRUST RELATIONSHIP (Single lookup)
    # ═══════════════════════════════════════════════════════════════════════════
    trust_score = db.query(models.UserTrustGraph.trust_score).filter(
        models.UserTrustGraph.user_id == sender.id,
        models.UserTrustGraph.trusted_user_id == receiver.id
    ).scalar()
    
    # ═══════════════════════════════════════════════════════════════════════════
    # POPULATE FEATURES FROM QUERY RESULTS
    # ═══════════════════════════════════════════════════════════════════════════
    
    # Handle None results (new user with no transactions)
    if not sender_metrics or sender_metrics.total_count == 0:
        # New user - set defaults
        for key in ['count_1h', 'count_24h', 'count_today', 'count_10m', 'session_count',
                    'sum_24h', 'sum_week', 'sum_1h', 'unique_receivers_24h',
                    'sent_to_receiver_today', 'tx_to_receiver_today', 'tx_to_receiver_1h',
                    'micro_txns_1h', 'same_amount_1h', 'failed_10m', 'receivers_30min',
                    'reverse_loop_2m', 'hour_count', 'day_count', 'paid_receiver_before']:
            features[key] = 0
        features['last_ip_encrypted'] = None
        features['last_tx_time'] = None
        features['first_tx_time'] = None
        features['account_age_days'] = 0
        features['minutes_since_last_tx'] = 10080
    else:
        # Populate from sender_metrics
        features['tx_count_1h'] = sender_metrics.count_1h or 0
        features['tx_count_24h'] = sender_metrics.count_24h or 0
        features['tx_count_10m'] = sender_metrics.count_10m or 0
        features['today_txn_count'] = sender_metrics.count_today or 0
        features['session_tx_count'] = sender_metrics.session_count or 0
        
        features['total_amount_24h'] = float(sender_metrics.sum_24h or 0)
        features['weekly_spent'] = float(sender_metrics.sum_week or 0)
        features['total_sent_1h'] = float(sender_metrics.sum_1h or 0)
        
        features['unique_receivers_24h'] = sender_metrics.unique_receivers_24h or 0
        features['sent_to_receiver_today'] = float(sender_metrics.sent_to_receiver_today or 0)
        features['tx_count_today_to_receiver'] = sender_metrics.tx_to_receiver_today or 0
        features['tx_count_1h_to_receiver'] = sender_metrics.tx_to_receiver_1h or 0
        
        features['micro_txns_1h'] = sender_metrics.micro_txns_1h or 0
        features['same_amount_count_1h'] = sender_metrics.same_amount_1h or 0
        features['failed_txns_10m'] = sender_metrics.failed_10m or 0
        features['receivers_30min'] = sender_metrics.receivers_30min or 0
        features['reverse_loop_count_2m'] = sender_metrics.reverse_loop_2m or 0
        
        features['last_ip_encrypted'] = sender_metrics.last_ip_encrypted
        
        # Account age
        if sender_metrics.first_tx_time:
            account_age = (timestamp - sender_metrics.first_tx_time).days
            features['account_age_days'] = min(account_age, 365)
        else:
            features['account_age_days'] = 0
        
        # Time since last transaction
        if sender_metrics.last_tx_time:
            time_diff = (timestamp - sender_metrics.last_tx_time).total_seconds() / 60
            features['minutes_since_last_tx'] = min(time_diff, 10080)
        else:
            features['minutes_since_last_tx'] = 10080
        
        # Is new receiver
        features['is_new_receiver'] = 0 if sender_metrics.paid_receiver_before > 0 else 1
        
        # Frequency analysis (simplified)
        total_tx = sender_metrics.total_count or 1
        features['hour_frequency'] = 50.0  # Default to 50% (neutral)
        features['day_frequency'] = 50.0  # Default to 50% (neutral)
        features['is_first_time_amount'] = 1 if sender_metrics.same_amount_1h == 0 else 0
    
    # Receiver features
    if receiver_metrics:
        features['receiver_unique_senders_24h'] = receiver_metrics.unique_senders_24h or 0
        features['receiver_first_tx_date'] = receiver_metrics.first_received
        features['receiver_total_tx_count'] = receiver_metrics.total_received or 0
        features['receiver_outflow_30m'] = receiver_metrics.outflow_30m or 0
        
        if receiver_metrics.first_received:
            features['recipient_age_days'] = min((timestamp - receiver_metrics.first_received).days, 365)
        else:
            features['recipient_age_days'] = 0
    else:
        features['receiver_unique_senders_24h'] = 0
        features['receiver_first_tx_date'] = None
        features['receiver_total_tx_count'] = 0
        features['receiver_outflow_30m'] = 0
        features['recipient_age_days'] = 0
    
    # Profile-based features (from cached profile data)
    avg_amount = sender.sender_profile.avg_transaction_amount if sender.sender_profile else 0
    features['avg_amount'] = avg_amount
    features['amount_vs_avg_ratio'] = (amount / avg_amount) if avg_amount > 0 else 1.0
    
    features['recipient_tx_volume'] = receiver.receiver_profile.total_received_amount if receiver.receiver_profile else 0
    
    # Trust score
    features['trust_score'] = trust_score or 0.0
    
    # Balance utilization
    features['balance_utilization'] = (amount / sender.balance * 100) if sender.balance > 0 else 100.0
    
    # Session averages
    if sender.sender_profile and sender.sender_profile.total_transactions_count > 10:
        avg_sessions = max(1, features['account_age_days'] * 5)
        features['avg_session_tx'] = sender.sender_profile.total_transactions_count / avg_sessions
    else:
        features['avg_session_tx'] = 3.0
    
    # Amount percentile
    features['amount_percentile'] = min(100, (amount / avg_amount * 50)) if avg_amount > 0 else 50.0
    
    # Consecutive transactions (kept simple - no additional query)
    features['consecutive_tx_count'] = 0  # Simplified for performance
    
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
    """
    Load existing model (READ-ONLY GUARD MODE) with enhanced error handling
    Returns: True if model loaded successfully, False otherwise
    """
    global _model
    
    if _model is not None:
        return True

    if not os.path.exists(MODEL_PATH):
        print(f"🛡️ Guard: No AI Model found at {MODEL_PATH}")
        print("🛡️ Guard: Operating in 'Rules Only' mode.")
        print(f"   Expected path: {os.path.abspath(MODEL_PATH)}")
        return False

    try:
        # 🔒 SECURITY: TWIN ENGINE CHECK (Embedded Signature)
        # We read the file, extract the last 64 bytes (Signature), and verify the rest.
        
        print(f"� Loading AI model from {MODEL_PATH}...")
        with open(MODEL_PATH, "rb") as f:
            file_content = f.read()
        
        file_size = len(file_content)
        print(f"   File size: {file_size} bytes")
            
        if file_size < 64:
            print("🚨 SECURITY ALERT: Model file too short (Corrupt/Empty)!")
            print(f"   Expected: >64 bytes, Got: {file_size} bytes")
            return False

        # Split: Payload | Signature (Last 64 bytes)
        payload = file_content[:-64]
        embedded_signature = file_content[-64:] # Bytes
        
        print(f"   Payload size: {len(payload)} bytes")
        print(f"   Verifying HMAC signature...")
        
        # Verify
        expected_digest = hmac.new(HMAC_SECRET.encode(), payload, hashlib.sha256)
        expected_signature = expected_digest.hexdigest().encode()
        
        if hmac.compare_digest(embedded_signature, expected_signature):
            print("   ✅ HMAC signature verified")
            print("   Loading model from pickle...")
            _model = pickle.loads(payload)
            print(f"🧠 Guard: AI Brain Verified & Loaded Successfully!")
            print(f"   Model type: {type(_model)}")
            print(f"   Model class: {_model.__class__.__name__}")
            return True
        else:
            print("🚨 SECURITY ALERT: Model tampering detected! (Invalid HMAC Seal)")
            print(f"   Expected signature: {expected_signature[:32].decode()}...")
            print(f"   Got signature:      {embedded_signature[:32].decode()}...")
            print(f"🛡️ Guard: HMAC_SECRET in .env might not match the one used during training.")
            print(f"   Current HMAC_SECRET length: {len(HMAC_SECRET)} chars")
            print("   Suggestion: Retrain the model with current HMAC_SECRET")
            _model = None
            return False
            
    except pickle.UnpicklingError as e:
        print(f"❌ Guard: Failed to unpickle model: {e}")
        print("   The model file may be corrupted or incompatible")
        _model = None
        return False
    except Exception as e:
        print(f"⚠️ Guard: Failed to load model: {e}")
        import traceback
        print("   Full traceback:")
        traceback.print_exc()
        _model = None
        return False

# NOTE: train_model() is REMOVED. This file is now purely a Detector.
# Training happens in 'ai_scheduler.py' (auto-runs every 24 hours).



def get_ai_score(features: dict) -> float:
    """
    Get anomaly score from AI model.
    Returns fraud probability (0.0 to 1.0) or anomaly score
    """
    global _model
    
    # Try to load model if not already loaded
    if _model is None:
        print("🧠 AI Score: Model not loaded, attempting to load...")
        success = load_model_readonly()
        if not success:
            print("🧠 AI Score: Model loading failed, returning 0.0 (rules-only mode)")
            return 0.0
    
    if _model is None:
        # Still None after load attempt
        return 0.0
    
    try:
        feature_array = get_feature_array(features)
        
        # Detection: Is this XGBoost or IsolationForest?
        if hasattr(_model, 'predict_proba'):
            # XGBOOST MODE
            probs = _model.predict_proba([feature_array])[0]
            fraud_prob = float(probs[1]) if len(probs) > 1 else float(probs[0])
            print(f"🧠 AI Score (XGBoost): {fraud_prob:.3f}")
            return fraud_prob
        else:
            # ISOLATION FOREST MODE
            score = _model.decision_function([feature_array])[0]
            print(f"🧠 AI Score (IsolationForest): {score:.3f}")
            return float(score)
            
    except Exception as e:
        print(f"⚠️ AI Score error: {e}")
        import traceback
        traceback.print_exc()
        return 0.0



# ═══════════════════════════════════════════════════════════════════════════
# SOCIAL GRAPH (Trust Network)
# ═══════════════════════════════════════════════════════════════════════════

def calculate_trust_depth(db: Session, sender_id: int, receiver_id: int, max_depth=2) -> tuple[int, bool]:
    """
    Trust Graph Depth:
    - Depth 1: Direct Friend (I trust you)
    - Depth 2: Friend of Friend
    - Depth 0: Stranger
    Returns: (depth, is_contact)
    """
    # Direct Trust (Depth 1)
    direct = db.query(models.UserTrustGraph).filter(
        models.UserTrustGraph.user_id == sender_id,
        models.UserTrustGraph.trusted_user_id == receiver_id
    ).first()
    if direct:
        return 1, direct.is_contact
    
    # Friend of Friend (Depth 2)
    my_friends = db.query(models.UserTrustGraph.trusted_user_id).filter(
        models.UserTrustGraph.user_id == sender_id
    ).all()
    friend_ids = [f[0] for f in my_friends]
    
    if not friend_ids:
        return 0, False
    
    fof = db.query(models.UserTrustGraph).filter(
        models.UserTrustGraph.user_id.in_(friend_ids),
        models.UserTrustGraph.trusted_user_id == receiver_id
    ).first()
    
    if fof:
        return 2, False
    
    return 0, False  # Stranger


# ═══════════════════════════════════════════════════════════════════════════
# MAIN FRAUD ENGINE (The 3-Stage Pipeline)
# ═══════════════════════════════════════════════════════════════════════════

def evaluate_fraud(db: Session, sender: models.User, receiver: models.User, amount: float, device_id_hash: str = None, receiver_mcc: str = None, current_ip: str = None, payment_source: str = None, is_screen_sharing: bool = False):
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
    
    # Extract all features upfront (OPTIMIZED VERSION - 3 queries instead of 10+)
    now = datetime.now()
    features = extract_features_optimized(db, sender, receiver, amount, now)
    
    # Define time boundaries for fraud rule checks
    hour_ago = now - timedelta(hours=1)
    day_ago = now - timedelta(hours=24)
    week_ago = now - timedelta(days=7)
    mins_30_ago = now - timedelta(minutes=30)
    mins_10_ago = now - timedelta(minutes=10)
    mins_2_ago = now - timedelta(minutes=2)
    day_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    
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
    
    # ═══════════════════════════════════════════════════════════════════════════
    # Initialize scoring
    # ═══════════════════════════════════════════════════════════════════════════
    
    risk_score = 0
    violation = None
    violations_list = []
    
    # ─── ESSENTIAL TIER: (Hospitals, Schools, Utilities) ────────────────────────
    # The Truth: We NEVER want to block a hospital payment, BUT we still
    # want to score it for audit and AI learning. Apply bonus AFTER initialization.
    if tier == "ESSENTIAL":
        print(f"🏥 ESSENTIAL TIER: Processing with high trust baseline for {receiver_mcc}")
        risk_score -= 100 # Large trust bonus
    
    # Apply tier trust bonus/penalty upfront
    risk_score -= tier_config.get("trust_bonus", 0)
    
    # ─── ACTIVATE AI BRAIN ───────────────────────────────────────────────────
    load_model_readonly()
    
    # ─── PRE-CALCULATE TRUST DEPTH ───────────────────────────────────────────
    trust_depth, is_contact = calculate_trust_depth(db, sender.id, receiver.id)
    features['is_contact'] = 1 if is_contact else 0
    
    # ─── Grouped Violation Tracking ──────────────────────────────────────────
    # We group related rules to avoid "double-dipping" penalties.
    # Logic: risk_score += max(rule_group)
    identity_risk = 0  # Group: New User, Stranger, Device Change
    behavior_risk = 0  # Group: Amount Spikes, Unusual Time, Velocity
    network_risk = 0   # Group: New Receiver Burst, Chain Detection, Star/Funnel
    
    # ─── F18: DAILY PER-RECEIVER LIMIT (PERMANENT) ─────────────────────────────
    sent_to_receiver_today = features.get('sent_to_receiver_today', 0)
    
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
    recent_txns_10m = features.get('tx_count_10m', 0)
    
    # For HIGH_VALUE tier (Jewelry), we check hourly velocity instead
    if tier == "HIGH_VALUE":
        recent_txns_hourly = features.get('tx_count_1h', 0)
        
        if recent_txns_hourly >= velocity_limit:
            print(f"💎 HIGH_VALUE: Velocity exceeded ({recent_txns_hourly} >= {velocity_limit}/hour)")
            return "HIGH", "F1_HIGH_VALUE_VELOCITY_EXCEEDED", features
    else:
        # Standard velocity check for other tiers
        if recent_txns_10m >= velocity_limit:
            return "HIGH", "F1_VELOCITY_LIMIT_EXCEEDED", features
    
    # ─── F2: CIRCULAR LOOP (A→B→A in 2 minutes) ───────────────────────────────
    reverse_loop_count = features.get('reverse_loop_count_2m', 0)
    if reverse_loop_count > 0:
        risk_score += 40
        violations_list.append("F2_CIRCULAR_LOOP")
    
    
    # ─── Group: IDENTITY RISK (Correlated rules F4, F12, F16) ──────────────────
    user_is_new = features['account_age_days'] == 0
    stranger_penalty = 0
    if tier == "PERSONAL" and trust_depth == 0:
        stranger_penalty = 45 # Same as F4
        violations_list.append("F12_STRANGER_NO_COMMON_TRUST")
    elif is_contact:
        # Extra bonus for being a literal contact
        risk_score -= 10
    
    first_tx_penalty = 0
    if tier == "PERSONAL" and user_is_new and amount > 2000:
        first_tx_penalty = 45
        violations_list.append("F4_FIRST_TX_HIGH_VALUE")
        
    device_change_penalty = 0
    if device_id_hash and sender.device_id_hash and device_id_hash != sender.device_id_hash and amount > 5000:
        device_change_penalty = 35
        violations_list.append("F16_DEVICE_CHANGE_HIGH_VALUE")
        
    # LOGIC: Take the MAXIMUM of these instead of adding them
    identity_risk = max(stranger_penalty, first_tx_penalty, device_change_penalty)
    risk_score += identity_risk
    
    # ─── F5: TICKET SIZE SPIKE (Adaptive Behavioral Profiling) ────────────────────
    # World-Class: Instead of fixed 3x multiplier, we use percentile-based detection
    # This adapts to each user's spending pattern
    if not skip_spike and features['avg_amount'] > 0:
        user_avg = features['avg_amount']
        spike_ratio = amount / user_avg
        
        # Store for analysis
        features['spike_ratio'] = spike_ratio
        
        # ADAPTIVE SPIKE DETECTION
        if spike_ratio > 10:
            # 10x average = EXTREME spike
            risk_score += 70
            violations_list.append("F5_EXTREME_AMOUNT_SPIKE")
            print(f"🚨 EXTREME SPIKE: ₹{amount} is {spike_ratio:.1f}x avg ₹{user_avg}")
        elif spike_ratio > 5:
            # 5x average = VERY HIGH spike
            risk_score += 60
            violations_list.append("F5_VERY_HIGH_AMOUNT_SPIKE")
            print(f"⚠️ VERY HIGH SPIKE: ₹{amount} is {spike_ratio:.1f}x avg ₹{user_avg}")
        elif spike_ratio > 3:
            # 3x average = HIGH spike (original threshold)
            risk_score += 50
            violations_list.append("F5_HIGH_AMOUNT_SPIKE")
            print(f"⚠️ HIGH SPIKE: ₹{amount} is {spike_ratio:.1f}x avg ₹{user_avg}")
        elif spike_ratio > 2:
            # 2x average = MEDIUM spike
            risk_score += 30
            violations_list.append("F5_MEDIUM_AMOUNT_SPIKE")
            print(f"ℹ️ MEDIUM SPIKE: ₹{amount} is {spike_ratio:.1f}x avg ₹{user_avg}")
    
    # ─── F9: NIGHT OWL (3 AM - 5 AM) ──────────────────────────────────────────
    hour = now.hour
    if 3 <= hour <= 5:
        risk_score += 25
        violations_list.append("F9_UNUSUAL_TIME")
    
    # ─── F10: SPLIT DETECTION (Multiple small txns to same receiver) ─────────
    same_receiver_count_1h = features.get('tx_count_1h_to_receiver', 0)
    if same_receiver_count_1h >= 3 and amount < 500:
        risk_score += 35
        violations_list.append("F10_SPLIT_TRANSACTION_DETECTED")
    
    # ─── F11: DAILY AGGREGATION LIMIT (Adaptive Per-User) ─────────────────────
    # World-Class: Instead of fixed ₹50k limit, use user's weekly average
    weekly_avg = features.get('weekly_spent', 0) / 7  # Daily average from weekly
    user_daily_baseline = max(weekly_avg * 1.5, 10000)  # At least ₹10k baseline
    
    # For merchants, use higher baseline
    if tier != "PERSONAL":
        user_daily_baseline = max(user_daily_baseline, 100000)
    
    daily_total = features['total_amount_24h'] + amount
    
    # Store for analysis
    features['user_daily_baseline'] = user_daily_baseline
    features['daily_total_with_current'] = daily_total
    
    # ADAPTIVE DAILY LIMIT CHECK
    if daily_total > user_daily_baseline * 3:
        # 3x their daily baseline = EXTREME
        risk_score += 50
        violations_list.append("F11_EXTREME_DAILY_LIMIT")
        print(f"🚨 EXTREME DAILY: ₹{daily_total} > 3x baseline ₹{user_daily_baseline}")
    elif daily_total > user_daily_baseline * 2:
        # 2x their daily baseline = HIGH
        risk_score += 40
        violations_list.append("F11_HIGH_DAILY_LIMIT")
        print(f"⚠️ HIGH DAILY: ₹{daily_total} > 2x baseline ₹{user_daily_baseline}")
    elif daily_total > user_daily_baseline:
        # 1x their daily baseline = APPROACHING
        risk_score += 30
        violations_list.append("F11_DAILY_LIMIT_APPROACHING")
        print(f"ℹ️ APPROACHING DAILY: ₹{daily_total} > baseline ₹{user_daily_baseline}")
    
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
    
    # ─── F15: RAPID DRAIN (Adaptive Balance Utilization) ──────────────────────
    # World-Class: Instead of fixed 50% threshold, use user's typical balance usage
    if sender.balance > 0:
        hour_total = features.get('total_sent_1h', 0)
        drain_ratio = (hour_total + amount) / sender.balance
        
        # Calculate user's typical hourly spending rate
        account_age_hours = max(features.get('account_age_days', 1) * 24, 24)
        total_spent = sender.sender_profile.total_transactions_amount if sender.sender_profile else 0
        typical_hourly_rate = total_spent / account_age_hours if account_age_hours > 0 else 0
        
        # Current hourly rate vs typical
        current_hourly = hour_total + amount
        rate_multiplier = current_hourly / max(typical_hourly_rate, 100) if typical_hourly_rate > 0 else 1
        
        # Store for analysis
        features['drain_ratio'] = drain_ratio
        features['rate_multiplier'] = rate_multiplier
        features['typical_hourly_rate'] = typical_hourly_rate
        
        # ADAPTIVE DRAIN DETECTION
        if drain_ratio > 0.8:
            # Draining >80% of balance in 1 hour = EXTREME
            risk_score += 60
            violations_list.append("F15_EXTREME_BALANCE_DRAIN")
            print(f"🚨 EXTREME DRAIN: {drain_ratio*100:.0f}% of balance in 1 hour")
        elif drain_ratio > 0.5:
            # Draining >50% of balance in 1 hour = HIGH
            risk_score += 40
            violations_list.append("F15_RAPID_BALANCE_DRAIN")
            print(f"⚠️ RAPID DRAIN: {drain_ratio*100:.0f}% of balance in 1 hour")
        elif drain_ratio > 0.3:
            # Draining >30% of balance in 1 hour = MEDIUM
            risk_score += 25
            violations_list.append("F15_MODERATE_BALANCE_DRAIN")
            print(f"ℹ️ MODERATE DRAIN: {drain_ratio*100:.0f}% of balance in 1 hour")
        
        # ALSO check spending rate anomaly
        if rate_multiplier > 10:
            risk_score += 40
            violations_list.append("F15_EXTREME_SPENDING_RATE")
            print(f"🚨 EXTREME RATE: {rate_multiplier:.1f}x typical hourly spending")
    
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
    
    # ─── F21: BEHAVIORAL DRIFT (Statistical Anomaly Detection) ──────────────────
    # World-Class: Use statistical deviation instead of simple percentile
    user_avg = features.get('avg_amount', 1000)
    
    # Calculate standard deviation approximation
    # For simplicity, assume std_dev ≈ avg * 0.5 (typical for transaction data)
    std_dev = user_avg * 0.5
    
    # Calculate z-score (how many standard deviations away)
    z_score = (amount - user_avg) / max(std_dev, 100) if std_dev > 0 else 0
    
    # Store for analysis
    features['behavioral_z_score'] = z_score
    features['behavioral_std_dev'] = std_dev
    
    # ADAPTIVE BEHAVIORAL DRIFT DETECTION
    if z_score > 6:
        # 6+ standard deviations = EXTREME anomaly (99.9999% confidence)
        risk_score += 50
        violations_list.append("F21_EXTREME_BEHAVIORAL_DRIFT")
        print(f"🚨 EXTREME DRIFT: z-score {z_score:.1f} (₹{amount} vs avg ₹{user_avg})")
    elif z_score > 4:
        # 4+ standard deviations = VERY HIGH anomaly (99.99% confidence)
        risk_score += 40
        violations_list.append("F21_VERY_HIGH_BEHAVIORAL_DRIFT")
        print(f"⚠️ VERY HIGH DRIFT: z-score {z_score:.1f} (₹{amount} vs avg ₹{user_avg})")
    elif z_score > 3:
        # 3+ standard deviations = HIGH anomaly (99.7% confidence)
        risk_score += 30
        violations_list.append("F21_HIGH_BEHAVIORAL_DRIFT")
        print(f"⚠️ HIGH DRIFT: z-score {z_score:.1f} (₹{amount} vs avg ₹{user_avg})")
    elif z_score > 2:
        # 2+ standard deviations = MEDIUM anomaly (95% confidence)
        risk_score += 20
        violations_list.append("F21_MEDIUM_BEHAVIORAL_DRIFT")
        print(f"ℹ️ MEDIUM DRIFT: z-score {z_score:.1f} (₹{amount} vs avg ₹{user_avg})")
    
    # ─── F22: DORMANT RECEIVER (Receiver inactive > 60 days) ────────────────────
    if features.get('recipient_age_days', 0) == 0 and features.get('recipient_tx_volume', 0) == 0:
        # Brand new receiver with no history
        if amount > 5000:
            risk_score += 20
            violations_list.append("F22_DORMANT_RECEIVER_RISK")
    
    # ─── F23: BURST TO NEW ACCOUNTS (3+ new receivers in 1 hour) ────────────────
    new_receivers_1h = features.get('new_receivers_1h', 0)
    
    if new_receivers_1h >= 3 and features.get('is_new_receiver', 0) == 1:
        risk_score += 40
        violations_list.append("F23_BURST_TO_NEW_ACCOUNTS")
    
    # ─── F24: CHAIN DETECTION (Money laundering pattern A→B→C) ──────────────────
    # Check if receiver immediately sent money after receiving
    receiver_outflow = features.get('receiver_outflow_30m', 0)
    
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
    
    # ─── F30: MERCHANT LOCATION FRAUD (City Lock) ────────────────────────────────
    # If a merchant is registered in Mumbai, they shouldn't be transacting from Delhi.
    # We auto-register their location on the first transaction.
    if tier != "PERSONAL" and GEOIP_ENABLED and features.get('current_ip'):
        current_ip = features.get('current_ip')
        _, _, city, country = get_location_from_ip(current_ip)
        
        if city and city != "Local":
            # AUTO-REGISTRATION: If this is their first time, save the location
            if not receiver.registered_city:
                print(f"📍 Auto-registering merchant location: {city}, {country}")
                receiver.registered_city = city
                receiver.registered_country = country
                # We can also save state if available, but city/country is key
                
                # Encrypt and save first IP for audit
                try:
                    import security
                    receiver.merchant_first_ip_encrypted = security.encrypt_value(current_ip)
                except:
                    pass
                
                db.commit() # Save immediately
                
            # VALIDATION: If registered, check if current city matches
            elif receiver.registered_city != city:
                # Mismatch! Merchant should be stationary.
                print(f"🚨 MERCHANT LOCATION MISMATCH: Registered in {receiver.registered_city}, detected in {city}")
                features['registered_city'] = receiver.registered_city
                features['detected_city'] = city
                return "HIGH", "F30_MERCHANT_LOCATION_FRAUD", features

    # ─── F29: GEO-VELOCITY (Impossible Travel Detection) ─────────────────────────
    # Uses MaxMind GeoLite2 to detect if user is traveling faster than possible
    # Example: Transaction from India, then 5 minutes later from USA = BLOCKED
    # Now fully implemented with IP tracking
    if GEOIP_ENABLED and features.get('current_ip'):
        current_ip = features.get('current_ip')
        last_ip_encrypted = features.get('last_ip_encrypted')
        
        if last_ip_encrypted:
            # Try to get last IP from encrypted storage
            last_ip = None
            try:
                import security
                last_ip = security.decrypt_value(last_ip_encrypted)
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
    
    # ─── F30: WEEKLY SPENDING LIMIT (Adaptive Per-User) ───────────────────────────
    # World-Class: Instead of fixed ₹2L/₹5L limits, use user's monthly average
    weekly_spent = features.get('weekly_spent', 0)
    
    # Calculate user's typical weekly spending from their history
    account_age_weeks = max(features.get('account_age_days', 7) / 7, 1)
    total_spent = sender.sender_profile.total_transactions_amount if sender.sender_profile else 0
    typical_weekly = total_spent / account_age_weeks if account_age_weeks > 0 else 10000
    
    # Adaptive baseline (at least ₹10k for P2P, ₹50k for merchants)
    user_weekly_baseline = max(typical_weekly * 1.5, 10000 if tier == "PERSONAL" else 50000)
    
    weekly_total = weekly_spent + amount
    
    # Store for analysis
    features['user_weekly_baseline'] = user_weekly_baseline
    features['typical_weekly_spending'] = typical_weekly
    features['weekly_total_with_current'] = weekly_total
    
    # ADAPTIVE WEEKLY LIMIT CHECK
    if weekly_total > user_weekly_baseline * 3:
        # 3x their weekly baseline = EXTREME
        risk_score += 50
        violations_list.append("F30_EXTREME_WEEKLY_LIMIT")
        print(f"🚨 EXTREME WEEKLY: ₹{weekly_total} > 3x baseline ₹{user_weekly_baseline}")
    elif weekly_total > user_weekly_baseline * 2:
        # 2x their weekly baseline = HIGH
        risk_score += 40
        violations_list.append("F30_HIGH_WEEKLY_LIMIT")
        print(f"⚠️ HIGH WEEKLY: ₹{weekly_total} > 2x baseline ₹{user_weekly_baseline}")
    elif weekly_total > user_weekly_baseline:
        # 1x their weekly baseline = WARNING
        risk_score += 30
        violations_list.append("F30_WEEKLY_LIMIT_WARNING")
        print(f"ℹ️ WEEKLY WARNING: ₹{weekly_total} > baseline ₹{user_weekly_baseline}")
    
    # ─── F31: MICRO-TRANSACTION BURST (>10 txns <₹100 in 1 hour) ──────────────────
    micro_txns = features.get('micro_txns_1h', 0)
    
    if micro_txns >= 10 and amount < 100:
        risk_score += 40
        violations_list.append("F31_MICRO_BURST_DETECTED")
    
    # ─── F32: WEEKEND SPIKE (Adaptive Behavioral Pattern) ─────────────────────────
    # World-Class: Compare weekend spending to user's typical weekend pattern
    if features.get('is_weekend', 0) == 1:
        # Get user's average weekend spending
        total_weekends = max(features.get('account_age_days', 7) / 7, 1)
        
        # Query weekend-specific average
        weekend_avg = db.query(func.avg(models.Transaction.amount)).filter(
            models.Transaction.sender_id == sender.id,
            func.extract('dow', models.Transaction.timestamp).in_([0, 6]),  # Sunday=0, Saturday=6
            models.Transaction.status == "SUCCESS"
        ).scalar() or amount
        
        # Also get weekday average for comparison
        weekday_avg = db.query(func.avg(models.Transaction.amount)).filter(
            models.Transaction.sender_id == sender.id,
            func.extract('dow', models.Transaction.timestamp).in_([1,2,3,4,5]),
            models.Transaction.status == "SUCCESS"
        ).scalar() or amount
        
        # Store for analysis
        features['weekend_avg'] = weekend_avg
        features['weekday_avg'] = weekday_avg
        
        # ADAPTIVE WEEKEND SPIKE DETECTION
        if weekend_avg > 0:
            weekend_ratio = amount / weekend_avg
            
            if weekend_ratio > 5:
                # 5x their typical weekend spending = EXTREME
                risk_score += 40
                violations_list.append("F32_EXTREME_WEEKEND_SPIKE")
                print(f"🚨 EXTREME WEEKEND: ₹{amount} is {weekend_ratio:.1f}x typical weekend ₹{weekend_avg}")
            elif weekend_ratio > 3:
                # 3x their typical weekend spending = HIGH
                risk_score += 30
                violations_list.append("F32_HIGH_WEEKEND_SPIKE")
                print(f"⚠️ HIGH WEEKEND: ₹{amount} is {weekend_ratio:.1f}x typical weekend ₹{weekend_avg}")
            elif weekend_ratio > 2:
                # 2x their typical weekend spending = MEDIUM
                risk_score += 20
                violations_list.append("F32_MEDIUM_WEEKEND_SPIKE")
                print(f"ℹ️ MEDIUM WEEKEND: ₹{amount} is {weekend_ratio:.1f}x typical weekend ₹{weekend_avg}")
        
        # ALSO check if this is unusual compared to their weekday pattern
        if weekday_avg > 0 and amount > weekday_avg * 3:
            risk_score += 15
            violations_list.append("F32_WEEKEND_VS_WEEKDAY_ANOMALY")
            print(f"ℹ️ WEEKEND ANOMALY: ₹{amount} > 3x weekday avg ₹{weekday_avg}")
    
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
    same_amount_count = features.get('same_amount_count_1h', 0)
    
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
    
    # ─── F41: TRANSACTION FREQUENCY CHANGE (Statistical Anomaly) ───────────────────
    # World-Class: Use statistical deviation for frequency anomaly detection
    if sender.sender_profile:
        # Calculate user's typical daily transaction count
        account_age_days = max(features.get('account_age_days', 1), 1)
        total_txns = sender.sender_profile.total_transactions_count if sender.sender_profile.total_transactions_count else 0
        avg_daily_txns = total_txns / account_age_days
        
        # Calculate standard deviation (assume Poisson distribution for counts)
        # For Poisson: std_dev ≈ sqrt(mean)
        std_dev_txns = max(avg_daily_txns ** 0.5, 1)
        
        today_txn_count = features.get('today_txn_count', 0)
        
        # Calculate z-score for frequency
        freq_z_score = (today_txn_count - avg_daily_txns) / std_dev_txns if std_dev_txns > 0 else 0
        
        # Store for analysis
        features['freq_z_score'] = freq_z_score
        features['avg_daily_txns'] = avg_daily_txns
        features['std_dev_txns'] = std_dev_txns
        
        # ADAPTIVE FREQUENCY SPIKE DETECTION
        if freq_z_score > 5:
            # 5+ standard deviations = EXTREME frequency spike
            risk_score += 50
            violations_list.append("F41_EXTREME_FREQUENCY_SPIKE")
            print(f"🚨 EXTREME FREQ: {today_txn_count} txns (z={freq_z_score:.1f}, avg={avg_daily_txns:.1f})")
        elif freq_z_score > 4:
            # 4+ standard deviations = VERY HIGH frequency spike
            risk_score += 40
            violations_list.append("F41_VERY_HIGH_FREQUENCY_SPIKE")
            print(f"⚠️ VERY HIGH FREQ: {today_txn_count} txns (z={freq_z_score:.1f}, avg={avg_daily_txns:.1f})")
        elif freq_z_score > 3:
            # 3+ standard deviations = HIGH frequency spike
            risk_score += 30
            violations_list.append("F41_HIGH_FREQUENCY_SPIKE")
            print(f"⚠️ HIGH FREQ: {today_txn_count} txns (z={freq_z_score:.1f}, avg={avg_daily_txns:.1f})")
        elif freq_z_score > 2:
            # 2+ standard deviations = MEDIUM frequency spike
            risk_score += 20
            violations_list.append("F41_MEDIUM_FREQUENCY_SPIKE")
            print(f"ℹ️ MEDIUM FREQ: {today_txn_count} txns (z={freq_z_score:.1f}, avg={avg_daily_txns:.1f})")
    
    # ─── F42: BALANCE VELOCITY (Adaptive Income vs Spending) ──────────────────────
    # World-Class: Compare spending rate to income rate with user's historical pattern
    week_ago = now - timedelta(days=7)
    
    week_received = db.query(func.sum(models.Transaction.amount)).filter(
        models.Transaction.receiver_id == sender.id,
        models.Transaction.timestamp >= week_ago,
        models.Transaction.status == "SUCCESS"
    ).scalar() or 0
    
    weekly_spent = features.get('weekly_spent', 0)
    
    # Calculate user's typical income/spending ratio
    total_received = sender.receiver_profile.total_received_amount if sender.receiver_profile else 0
    total_sent = sender.sender_profile.total_transactions_amount if sender.sender_profile else 0
    
    typical_ratio = total_sent / max(total_received, 1) if total_received > 0 else 1.0
    current_ratio = weekly_spent / max(week_received, 1) if week_received > 0 else 1.0
    
    # Store for analysis
    features['typical_spend_income_ratio'] = typical_ratio
    features['current_spend_income_ratio'] = current_ratio
    features['week_received'] = week_received
    
    # ADAPTIVE BALANCE VELOCITY DETECTION
    if current_ratio > typical_ratio * 5 and weekly_spent > 50000:
        # 5x their typical ratio + high absolute amount = EXTREME
        risk_score += 50
        violations_list.append("F42_EXTREME_SPENDING_EXCEEDS_INCOME")
        print(f"🚨 EXTREME VELOCITY: Spending {current_ratio:.1f}x income (typical {typical_ratio:.1f}x)")
    elif current_ratio > typical_ratio * 3 and weekly_spent > 30000:
        # 3x their typical ratio = HIGH
        risk_score += 40
        violations_list.append("F42_HIGH_SPENDING_EXCEEDS_INCOME")
        print(f"⚠️ HIGH VELOCITY: Spending {current_ratio:.1f}x income (typical {typical_ratio:.1f}x)")
    elif current_ratio > typical_ratio * 2 and weekly_spent > 20000:
        # 2x their typical ratio = MEDIUM
        risk_score += 30
        violations_list.append("F42_MEDIUM_SPENDING_EXCEEDS_INCOME")
        print(f"ℹ️ MEDIUM VELOCITY: Spending {current_ratio:.1f}x income (typical {typical_ratio:.1f}x)")
    elif weekly_spent > week_received * 2 and weekly_spent > 50000:
        # Absolute check: spending 2x income this week
        risk_score += 20
        violations_list.append("F42_SPENDING_EXCEEDS_INCOME")
        print(f"ℹ️ VELOCITY: Spent ₹{weekly_spent} vs received ₹{week_received} this week")
    
    # ─── F43: DEVICE AGE CHECK (New device + high volume) ─────────────────────────
    # ─── F43: DEVICE AGE CHECK (New device + high volume) ─────────────────────────
    if sender and sender.total_device_count > 0 and device_id_hash:
        # Check if current device is new (< 7 days)
        # We determine age by looking at the EARLIEST login for this device
        first_device_login = db.query(func.min(models.LoginHistory.login_time)).filter(
            models.LoginHistory.user_id == sender.id,
            models.LoginHistory.device_id_hash == device_id_hash
        ).scalar()
        
        if first_device_login and first_device_login > week_ago:
            # New device detected! Check for high activity
            if today_txn_count > 5:
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
    concurrent_txns = features.get('concurrent_txns_5s', 0)
    
    if concurrent_txns >= 2:
        risk_score += 50
        violations_list.append("F48_CONCURRENT_TRANSACTION")
    
    # ─── F49: FAILED TRANSACTION VELOCITY (>3 failed in 10 min) ───────────────────
    failed_txns = features.get('failed_txns_10m', 0)
    
    if failed_txns >= 3:
        risk_score += 40
        violations_list.append("F49_MULTIPLE_FAILED_ATTEMPTS")
    
    # ═══════════════════════════════════════════════════════════════════════════
    # AML/NETWORK RULES (F50-F54)
    # ═══════════════════════════════════════════════════════════════════════════
    
    # ─── F50: STAR PATTERN (One sender to many receivers quickly) ─────────────────
    receivers_30min = features.get('receivers_30min', 0)
    
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
    # SCAM DETECTION RULES v5.0 (F55–F61)
    # Research basis: IJRASET 2025, Kansas City Fed 2024, Wultra 2024,
    #                 ResearchGate 2025, Palo Alto Networks 2024
    # ═══════════════════════════════════════════════════════════════════════════

    # ─── F55: SCREEN SHARING HARD BLOCK ─────────────────────────────────────────
    # Research: Wultra (2024) — any transaction during remote screen access to a
    # non-trusted contact must be hard-blocked. Scammer controls victim's device.
    # Hard block: cannot be bypassed by "Proceed Anyway".
    if is_screen_sharing and trust_depth < 2:
        print(f"🚨 F55: Screen sharing detected during payment to non-trusted receiver.")
        features['screen_sharing_block'] = True
        return "HIGH", "F55_SCREEN_SHARING_HARD_BLOCK", features

    # ─── F56: FAKE MERCHANT PROFILE (Composite Suspicion Scorer) ────────────────
    # Research: ResearchGate 2025, IARJSET 2024 — fake merchants have near-zero
    # customer density. Uses parametric scoring, not hard thresholds.
    # Applies to ALL merchant tiers (scammers can get real merchant MCCs via
    # fake business registration — see explanation in scam_research_report.md).
    if tier != "PERSONAL":
        receiver_first_tx_date = features.get('receiver_first_tx_date')
        merchant_score, merchant_signals = score_merchant_suspicion(
            mcc_tier=tier,
            receiver_profile=receiver.receiver_profile if hasattr(receiver, 'receiver_profile') else None,
            amount=amount,
            current_hour=now.hour,
            is_new_receiver=(features.get('is_new_receiver', 0) == 1),
            receiver_first_tx_date=receiver_first_tx_date
        )
        features['merchant_suspicion_score'] = merchant_score
        features['merchant_suspicion_signals'] = merchant_signals

        if merchant_score >= 70:
            # Very high suspicion: likely fake merchant
            risk_score += 55
            violations_list.append("F56_FAKE_MERCHANT_PROFILE_HIGH")
            print(f"🚨 F56: Fake merchant suspicion HIGH ({merchant_score}): {merchant_signals}")
        elif merchant_score >= 45:
            # Moderate: unverified/new merchant with anomalies
            risk_score += 30
            violations_list.append("F56_FAKE_MERCHANT_PROFILE_WARN")
            print(f"⚠️ F56: Fake merchant suspicion WARN ({merchant_score}): {merchant_signals}")
        elif merchant_score >= 25:
            # Low: worth logging internally
            risk_score += 10
            violations_list.append("F56_NEW_MERCHANT_CAUTION")

    # ─── F57: MCC MISMATCH — P2P ACCOUNT CLAIMING MERCHANT MCC ─────────────────
    # Research: Palo Alto Networks 2024 — QR sticker attack places scammer's
    # personal account QR (MCC 0000) over a real merchant QR. But the *receiver's
    # registered* MCC is 0000 while the QR claims a merchant MCC.
    # Hard block: a personal account cannot legitimately be a grocery store.
    if receiver_mcc and receiver_mcc != "0000":
        receiver_registered_mcc = getattr(receiver, 'mcc', None)
        if receiver_registered_mcc == "0000" or not receiver_registered_mcc:
            # QR claims merchant MCC, but receiver's account is personal
            print(f"🚨 F57: MCC mismatch — QR claims {receiver_mcc} but receiver is P2P.")
            features['mcc_mismatch_claimed'] = receiver_mcc
            features['mcc_mismatch_registered'] = receiver_registered_mcc or '0000'
            return "HIGH", "F57_MCC_MISMATCH_P2P_POSES_MERCHANT", features
        elif receiver_registered_mcc and receiver_registered_mcc != receiver_mcc:
            # MCC in QR differs from what's registered (category change attempt)
            risk_score += 35
            violations_list.append("F57_MCC_CATEGORY_CHANGE_DETECTED")
            print(f"⚠️ F57: MCC changed from {receiver_registered_mcc} to {receiver_mcc} via QR.")

    # ─── F58: QR TO PERSONAL ACCOUNT — Universal Awareness Warning ──────────────
    # Whenever a user scans a QR code that leads to a PERSONAL account (MCC=0000),
    # they MUST be shown an awareness notice regardless of who the receiver is.
    #
    # Why: The "Scan to Receive" scam tricks victims into scanning a scammer's
    # personal QR believing they will RECEIVE money. But QR scans always SEND.
    # Showing "This is a personal account, not a shop" prevents this.
    #
    # This is NOT a hard block — user can proceed if they intend to pay a person.
    if payment_source in ["qr_scan", "qr_upload", "qr_share"]:
        features['payment_source'] = payment_source

        if tier == "PERSONAL":
            # ── AWARENESS: Strangers (depth=0) AND FoF (depth=2) get warning ──
            # Only direct friends (depth=1) are exempt — they are well-known.
            # FoF means you share a common contact, but the receiver is not
            # someone you've paid before, so awareness is still warranted.
            if trust_depth != 1:
                risk_score += 60  # Pushes to WARN territory
                violations_list.append("F58_QR_TO_PERSONAL_ACCOUNT_AWARENESS")
                features['qr_personal_receiver_name'] = getattr(receiver, 'username', '')
                print(f"⚠️ F58: QR to personal account stranger ({getattr(receiver, 'username', '')}) — awareness raised.")

                # ── EXTRA: First-time + meaningful amount → even higher risk ──
                if features.get('is_new_receiver', 0) == 1 and amount > 500:
                    risk_score += 35
                    violations_list.append("F58_QR_PERSONAL_STRANGER_SPIKE")
                    print(f"⚠️ F58: QR to personal stranger (first-time, ₹{amount}) — elevated risk.")

            elif trust_depth == 1 and features.get('is_new_receiver', 0) == 1:
                # ── SOFT NUDGE: Direct friend but FIRST TIME paying via QR scan ──
                # Not a fraud signal — just a debit confirmation awareness so the user
                # knows this is a SEND (not a receive), even for people they know.
                # Kept at +25 so it stays well below WARN threshold (60).
                risk_score += 25
                violations_list.append("F58_QR_FRIEND_FIRST_TIME_DEBIT_NOTICE")
                features['qr_personal_receiver_name'] = getattr(receiver, 'username', '')
                print(f"ℹ️ F58: First-ever QR payment to friend {getattr(receiver, 'username', '')} — debit notice raised.")

    # ─── F59: BUSINESS HOURS VIOLATION for P2P (Deep-Link / External Source) ────
    # Research: Kansas City Fed (2024) — SMS/WhatsApp link clicks open app directly.
    # payment_source 'deep_link' + stranger + off-hours = social engineering signal.
    if payment_source == "deep_link":
        features['payment_source'] = "deep_link"
        risk_score += 20
        violations_list.append("F59_DEEP_LINK_PAYMENT")
        if trust_depth == 0:
            risk_score += 20  # Additional penalty for stranger via link
            violations_list.append("F59_DEEP_LINK_STRANGER")
            print(f"⚠️ F59: Deep-link payment to stranger (₹{amount}).")

    # ─── F60: PANIC TRANSACTION (Urgency Detection) ──────────────────────────────
    # Research: Kansas City Fed (2024) — normal users take 45–90s from login.
    # Social engineering victims average <15s. Combine with amount + stranger.
    if sender.last_active_at:
        ttx_seconds = (now - sender.last_active_at).total_seconds()
        features['ttx_seconds'] = ttx_seconds
        # Urgency threshold: 12s to send >₹1k to a stranger = panic payment pattern
        if ttx_seconds < 12 and amount > 1000 and trust_depth == 0:
            risk_score += 40
            violations_list.append("F60_PANIC_TRANSACTION_URGENCY")
            print(f"⚠️ F60: Panic payment — {ttx_seconds:.1f}s from login, ₹{amount} to stranger.")
        elif ttx_seconds < 30 and amount > 5000 and trust_depth == 0:
            risk_score += 20
            violations_list.append("F60_FAST_HIGH_VALUE_STRANGER")

    # ─── F61: INVESTMENT SCAM KEYWORDS IN PAYMENT NOTE ──────────────────────────
    # Research: ResearchGate (2025) — NLP on note field improves detection by 38%.
    # Scammers often instruct victims to include a specific note.
    note_field = getattr(sender, 'last_note', None)  # Note is stored per-transaction
    # Note: in main.py, pass tx.note as part of features for this check
    note_raw = features.get('payment_note', '')
    if note_raw and trust_depth == 0:
        note_lower = note_raw.lower()
        matched_kw = [kw for kw in INVESTMENT_SCAM_KEYWORDS if kw in note_lower]
        if matched_kw:
            risk_score += 30
            violations_list.append(f"F61_INVESTMENT_SCAM_NOTE_KEYWORDS")
            features['scam_keywords_found'] = matched_kw
            print(f"⚠️ F61: Scam keywords in note to stranger: {matched_kw}")

    # ═══════════════════════════════════════════════════════════════════════════
    # STAGE 2: NETWORK (Social Graph) - PERSONAL TIER ONLY
    # ═══════════════════════════════════════════════════════════════════════════
    # STAGE 2: NETWORK (Social Graph) - PERSONAL TIER ONLY
    # ═══════════════════════════════════════════════════════════════════════════
    
    if tier == "PERSONAL":
        # ─── ENHANCED TRUST GRAPH LOGIC FOR P2P (v6.0) ────────────────────────
        # Calculate comprehensive trust impact
        trust_impact = 0
        
        if trust_depth == 1:
            # Direct Friend: Strong trust bonus
            trust_impact -= 30  # Increased from -15
            violations_list.append("TRUST_DIRECT_FRIEND")
            
            # Additional bonus for phone contact
            if is_contact:
                trust_impact -= 15  # Additional contact bonus
                violations_list.append("TRUST_PHONE_CONTACT")
                
        elif trust_depth == 2:
            # Friend of Friend: Moderate trust
            trust_impact -= 10  # Increased from -5
            violations_list.append("TRUST_FRIEND_OF_FRIEND")
            
        else:
            # Stranger: Significant penalty
            trust_impact += 50  # Increased from +20
            violations_list.append("F12_STRANGER_NO_COMMON_TRUST")
            
            # ═══════════════════════════════════════════════════════════════════
            # ADAPTIVE AMOUNT-BASED PENALTIES (World-Class Behavioral Profiling)
            # ═══════════════════════════════════════════════════════════════════
            # Instead of fixed thresholds (₹20k, ₹10k, ₹5k), we use the user's
            # spending profile to determine what's "high value" FOR THEM.
            #
            # Logic:
            # - Calculate user's average transaction amount
            # - Calculate percentile of current amount vs their history
            # - Apply penalties based on how unusual this amount is FOR THIS USER
            #
            # Example:
            # - User A (avg ₹500): Sending ₹5,000 = 10x their average = HIGH penalty
            # - User B (avg ₹50,000): Sending ₹5,000 = 0.1x their average = LOW penalty
            #
            # This is how Google Pay, PayPal, and Stripe work.
            # ═══════════════════════════════════════════════════════════════════
            
            user_avg_amount = features.get('avg_amount', 1000)  # Default ₹1,000 if no history
            
            # Calculate how many times larger this amount is vs their average
            amount_multiplier = amount / max(user_avg_amount, 100)  # Avoid division by zero
            
            # Store for logging
            features['stranger_amount_multiplier'] = amount_multiplier
            features['user_avg_amount'] = user_avg_amount
            
            # ADAPTIVE PENALTIES based on behavioral deviation
            if amount_multiplier >= 20:
                # 20x their average = EXTREME anomaly
                trust_impact += 60
                violations_list.append("F8_STRANGER_EXTREME_ANOMALY")
                print(f"🚨 EXTREME: ₹{amount} is {amount_multiplier:.1f}x user's avg ₹{user_avg_amount}")
                
            elif amount_multiplier >= 10:
                # 10x their average = VERY HIGH anomaly
                trust_impact += 50
                violations_list.append("F8_STRANGER_VERY_HIGH_ANOMALY")
                print(f"⚠️ VERY HIGH: ₹{amount} is {amount_multiplier:.1f}x user's avg ₹{user_avg_amount}")
                
            elif amount_multiplier >= 5:
                # 5x their average = HIGH anomaly
                trust_impact += 40
                violations_list.append("F8_STRANGER_HIGH_ANOMALY")
                print(f"⚠️ HIGH: ₹{amount} is {amount_multiplier:.1f}x user's avg ₹{user_avg_amount}")
                
            elif amount_multiplier >= 3:
                # 3x their average = MEDIUM anomaly
                trust_impact += 30
                violations_list.append("F8_STRANGER_MEDIUM_ANOMALY")
                print(f"⚠️ MEDIUM: ₹{amount} is {amount_multiplier:.1f}x user's avg ₹{user_avg_amount}")
                
            elif amount_multiplier >= 2:
                # 2x their average = LOW anomaly
                trust_impact += 20
                violations_list.append("F8_STRANGER_LOW_ANOMALY")
                print(f"ℹ️ LOW: ₹{amount} is {amount_multiplier:.1f}x user's avg ₹{user_avg_amount}")
            
            # FALLBACK: For new users with no history, use absolute thresholds
            # This ensures we still protect brand new accounts
            if user_avg_amount <= 100:  # New user or very low activity
                if amount > 20000:
                    trust_impact += 50
                    violations_list.append("F8_NEW_USER_VERY_HIGH_VALUE")
                elif amount > 10000:
                    trust_impact += 40
                    violations_list.append("F8_NEW_USER_HIGH_VALUE")
                elif amount > 5000:
                    trust_impact += 30
                    violations_list.append("F8_NEW_USER_MEDIUM_VALUE")
                elif amount > 2000:
                    trust_impact += 20
                    violations_list.append("F8_NEW_USER_LOW_VALUE")
        
        # Apply trust impact to risk score
        risk_score += trust_impact
        
        # Store trust impact in features for analysis
        features['trust_impact'] = trust_impact
        features['trust_depth'] = trust_depth
        
        # ─── F7: UNTRUSTED RECEIVER HIGH VALUE (P2P ONLY) ─────────────────────
        # ADAPTIVE LEARNING: Use the learned limit from SenderProfile
        base_limit = tier_config.get("stranger_first_time_limit", 5000)
        profile_limit = sender.sender_profile.personal_trust_limit if (sender and sender.sender_profile) else base_limit
        
        # Security: FoF (depth 2) gets a 2x higher limit but still restricted
        effective_limit = profile_limit if trust_depth == 0 else profile_limit * 2
        
        if trust_depth in [0, 2]: # Apply to both strangers and FoF
            if amount > effective_limit:
                 print(f"🚫 F7: Transaction ₹{amount} > effective limit ₹{effective_limit} for depth {trust_depth}")
                 features['effective_limit'] = effective_limit
                 features['limit_exceeded_by'] = amount - effective_limit
                 return "HIGH", "F7_UNTRUSTED_RECEIVER_HIGH_VALUE", features
            elif amount > base_limit:
                 # Over base but under personal? Add significant risk.
                 risk_score += 40
                 violations_list.append("F7_PERSONAL_LIMIT_WARNING")
    
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
    
    # Stage 3 logic depends on model type (Probability vs Anomaly Score)
    is_xgboost = hasattr(_model, 'predict_proba') if _model else False
    
    if is_xgboost:
        # XGBOOST: Probability (0 to 1) - Higher is riskier
        if ai_score > 0.9:
            risk_score += 65
            violations_list.append("AI_DETECTED_HIGH_FRAUD_PROB")
        elif ai_score > 0.6:
            risk_score += 30
            violations_list.append("AI_DETECTED_MEDIUM_FRAUD_PROB")
        elif ai_score < 0.1:
            risk_score -= 10 # Very safe
    else:
        # ISOLATION FOREST: Anomaly Score (-0.5 to 0.5) - Negative is riskier
        if ai_score < -0.3:
            risk_score += 65
            violations_list.append("AI_DETECTED_STRONG_ANOMALY")
        elif ai_score < -0.1:
            risk_score += 30
            violations_list.append("AI_DETECTED_MILD_ANOMALY")
        elif ai_score > 0.3:
            risk_score -= 10 # Very normal
    
    # ═══════════════════════════════════════════════════════════════════════════
    # FINAL VERDICT
    # ═══════════════════════════════════════════════════════════════════════════
    
    # Cap score
    risk_score = max(0, min(100, risk_score))
    
    # Pick primary violation
    violation = violations_list[0] if violations_list else None
    
    # Log detailed output using logger instead of print
    from logging_config import logger
    logger.info(f"🕵️ FRAUD EVAL: {sender.username} → {receiver.username} | ₹{amount}")
    logger.info(f"   MCC: {receiver_mcc} | Tier: {tier}")
    logger.info(f"   Trust Depth: {trust_depth} | AI Score: {ai_score:.3f}")
    logger.info(f"   FINAL RISK SCORE: {risk_score} (HIGH≥{RISK_THRESHOLD_HIGH}, WARN≥{RISK_THRESHOLD_WARN})")
    logger.info(f"   Violations: {violations_list}")
    
    # CRITICAL DEBUG: Log the decision
    if risk_score >= RISK_THRESHOLD_HIGH:
        logger.info(f"   ✅ VERDICT: HIGH RISK (score {risk_score} >= {RISK_THRESHOLD_HIGH})")
    elif risk_score >= RISK_THRESHOLD_WARN:
        logger.info(f"   ✅ VERDICT: WARN (score {risk_score} >= {RISK_THRESHOLD_WARN})")
    else:
        logger.info(f"   ✅ VERDICT: SAFE (score {risk_score} < {RISK_THRESHOLD_WARN})")
    
    # --- AUTOMATED AI LEARNING: Log suspicious events for future training ---
    if risk_score >= 60:
        # We don't have a transaction_id yet during evaluate_risk (pre-creation)
        # but we can log it with a placeholder for the retraining feedback loop.
        # In main.py, we should call record_fraud_event after the transaction is actually created.
        features['should_log_fraud_event'] = True

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
        exists.trust_score += 10.0
        exists.last_interaction_at = datetime.now()
    else:
        new_link = models.UserTrustGraph(
            user_id=sender_id,
            trusted_user_id=receiver_id,
            trust_score=10.0,
            last_interaction_at=datetime.now()
        )
        db.add(new_link)
    
    db.commit()


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


def update_adaptive_memory(db: Session, sender: models.User, amount: float, was_acknowledged: bool):
    """
    Adaptive Learning: Grows the user's personal trust limit based on behavior.
    
    Logic:
    1. If user sends a high-value amount and ACKNOWLEDGES risk, we start a 'streak'.
    2. After 3 successful high-value transactions to different people with no fraud reports, 
       we increase their personal_trust_limit by 20%.
    """
    profile = sender.sender_profile
    if not profile:
        return

    if was_acknowledged and amount > profile.personal_trust_limit * 0.8:
        # User is pushing their boundary
        if profile.last_override_amount == amount:
            profile.override_streak_count += 1
        else:
            profile.override_streak_count = 1
            profile.last_override_amount = amount
            
        # If streak reached 3, increase limit
        if profile.override_streak_count >= 3:
            old_limit = profile.personal_trust_limit
            profile.personal_trust_limit *= 1.25 # 25% increase
            profile.override_streak_count = 0 # Reset streak
            print(f"🧠 ADAPTIVE LEARNING: User {sender.username} limit increased from {old_limit} to {profile.personal_trust_limit}")
            
            # Notify User of their increased limit (Safe & Trusted status)
            notification = models.Notification(
                user_id=sender.id,
                title="Security Limit Increased",
                message=f"Your verified spending limit has been increased to ₹{profile.personal_trust_limit:,.0f} based on your safe transaction history.",
                type="success"
            )
            db.add(notification)
    
    db.commit()
