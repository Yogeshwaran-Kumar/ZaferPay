"""
test_scam_rules.py  -  Offline unit tests for new fraud detection rules v5.0
Tests score_merchant_suspicion(), HARD_BLOCK_REASONS, MCC configs, keywords, and signature.
"""

import sys, os, types
from unittest.mock import MagicMock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# ── Stub 'models' ─────────────────────────────────────────────────────────────
models_stub = types.ModuleType('models')
for cls in ['User', 'UserTrustGraph', 'Transaction', 'SenderProfile',
            'ReceiverProfile', 'LoginHistory', 'FraudEvent']:
    setattr(models_stub, cls, type(cls, (), {}))
sys.modules['models'] = models_stub

# ── Stub 'auth' ───────────────────────────────────────────────────────────────
auth_stub = types.ModuleType('auth')
auth_stub.HMAC_SECRET = 'test_secret'
sys.modules['auth'] = auth_stub

# ── Stub 'security' ───────────────────────────────────────────────────────────
security_stub = types.ModuleType('security')
security_stub.hash_value = lambda x: x
security_stub.encrypt_value = lambda x: x
security_stub.decrypt_value = lambda x: x
sys.modules['security'] = security_stub

# ── Stub geoip2 (Reader returns stub, .city() raises so GEOIP_ENABLED=True but queries fail gracefully) ──
geoip2_db_stub = types.ModuleType('geoip2.database')
class _FakeReader:
    """Succeeds on __init__ so fraud_engine marks GEOIP_ENABLED=True, 
    but all city() lookups raise so the engine falls back gracefully."""
    def __init__(self, path): pass
    def city(self, ip): raise Exception("stub: no real DB")
geoip2_db_stub.Reader = _FakeReader
geoip2_stub = types.ModuleType('geoip2')
geoip2_stub.database = geoip2_db_stub
sys.modules['geoip2'] = geoip2_stub
sys.modules['geoip2.database'] = geoip2_db_stub

# ── Stub sqlalchemy ───────────────────────────────────────────────────────────
sa_stub = types.ModuleType('sqlalchemy')
sa_stub.func = MagicMock()
sys.modules['sqlalchemy'] = sa_stub
sa_orm_stub = types.ModuleType('sqlalchemy.orm')
sa_orm_stub.Session = MagicMock
sys.modules['sqlalchemy.orm'] = sa_orm_stub

# ── Import the module under test ──────────────────────────────────────────────
import fraud_engine as fe

# =============================================================================
# TESTS
# =============================================================================

print("\n── TEST 1: HARD_BLOCK_REASONS ──")
assert "F55_SCREEN_SHARING_HARD_BLOCK" in fe.HARD_BLOCK_REASONS
assert "F57_MCC_MISMATCH_P2P_POSES_MERCHANT" in fe.HARD_BLOCK_REASONS
print(f"  PASS: {len(fe.HARD_BLOCK_REASONS)} entries, F55 and F57 present")

print("\n── TEST 2: MCC Parametric Configs ──")
for tier in ['ESSENTIAL', 'HIGH_VALUE', 'RETAIL', 'SERVICES', 'PERSONAL']:
    assert tier in fe.MCC_BUSINESS_HOURS
    assert tier in fe.MCC_TYPICAL_AMOUNT
    assert tier in fe.MCC_MIN_SENDER_DENSITY
    biz = fe.MCC_BUSINESS_HOURS[tier]
    assert len(biz) == 2
    amt = fe.MCC_TYPICAL_AMOUNT[tier]
    assert amt[0] < amt[1]
print("  PASS: All 5 MCC tiers configured in all 3 config dicts")

print("\n── TEST 3: ESSENTIAL tier always trusted ──")
score, signals = fe.score_merchant_suspicion(
    mcc_tier='ESSENTIAL', receiver_profile=None, amount=50000,
    current_hour=3, is_new_receiver=True, receiver_first_tx_date=None
)
assert score == 0 and signals == []
print(f"  PASS: score={score}, signals={signals}")

print("\n── TEST 4: Brand new RETAIL merchant is suspicious ──")
score, signals = fe.score_merchant_suspicion(
    mcc_tier='RETAIL', receiver_profile=None, amount=500,
    current_hour=14, is_new_receiver=True, receiver_first_tx_date=None
)
assert score > 0
assert any('HISTORY' in s or 'NEW' in s for s in signals)
print(f"  PASS: score={score}, signals={signals}")

print("\n── TEST 5: RETAIL merchant receiving Rs.40,000 (max Rs.15,000) ──")
from datetime import datetime, timedelta
old_date = datetime.now() - timedelta(days=60)
profile = MagicMock()
profile.unique_senders_count = 100
score, signals = fe.score_merchant_suspicion(
    mcc_tier='RETAIL', receiver_profile=profile, amount=40000,
    current_hour=14, is_new_receiver=False, receiver_first_tx_date=old_date
)
amount_signals = [s for s in signals if 'AMOUNT' in s]
assert amount_signals, f"Expected AMOUNT signal, got {signals}"
print(f"  PASS: score={score}, amount_signals={amount_signals}")

print("\n── TEST 6: RETAIL merchant at 2 AM vs 2 PM ──")
profile2 = MagicMock()
profile2.unique_senders_count = 200
score_2am, signals_2am = fe.score_merchant_suspicion(
    mcc_tier='RETAIL', receiver_profile=profile2, amount=200,
    current_hour=2, is_new_receiver=False, receiver_first_tx_date=old_date
)
score_2pm, _ = fe.score_merchant_suspicion(
    mcc_tier='RETAIL', receiver_profile=profile2, amount=200,
    current_hour=14, is_new_receiver=False, receiver_first_tx_date=old_date
)
assert score_2am > score_2pm
biz_signals = [s for s in signals_2am if 'BUSINESS_HOURS' in s]
assert biz_signals, f"Expected BUSINESS_HOURS signal, got {signals_2am}"
print(f"  PASS: 2AM score={score_2am} > 2PM score={score_2pm}, {biz_signals}")

print("\n── TEST 7: Low sender density after 35 days ──")
old_35 = datetime.now() - timedelta(days=35)
low_profile = MagicMock()
low_profile.unique_senders_count = 1  # density ~0.028 vs expected 0.3 for RETAIL
score_low, signals_low = fe.score_merchant_suspicion(
    mcc_tier='RETAIL', receiver_profile=low_profile, amount=200,
    current_hour=12, is_new_receiver=False, receiver_first_tx_date=old_35
)
density_signals = [s for s in signals_low if 'DENSITY' in s]
assert density_signals, f"Expected DENSITY signal, got {signals_low}"
print(f"  PASS: score={score_low}, density_signals={density_signals}")

print("\n── TEST 8: INVESTMENT_SCAM_KEYWORDS ──")
scam_note = "send now to get daily income double returns"
hits = [kw for kw in fe.INVESTMENT_SCAM_KEYWORDS if kw in scam_note.lower()]
assert len(hits) >= 2, f"Expected >= 2 keyword hits, got: {hits}"
print(f"  PASS: matched keywords = {hits}")

print("\n── TEST 9: evaluate_fraud() signature ──")
import inspect
sig = inspect.signature(fe.evaluate_fraud)
params = list(sig.parameters.keys())
assert 'payment_source' in params, f"Missing payment_source in {params}"
assert 'is_screen_sharing' in params, f"Missing is_screen_sharing in {params}"
assert sig.parameters['payment_source'].default is None
assert sig.parameters['is_screen_sharing'].default == False
print("  PASS: payment_source and is_screen_sharing present with correct defaults")

print("\n\n  ALL 9 TESTS PASSED - QR/MCC fraud detection rules verified.\n")
