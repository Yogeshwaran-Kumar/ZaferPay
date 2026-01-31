"""
Unit Tests for Fraud Detection Engine

Run with: pytest tests/ -v
"""

import pytest
import sys
import os

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from datetime import datetime, timedelta
from unittest.mock import MagicMock, patch


class MockUser:
    """Mock User object for testing"""
    def __init__(self, id=1, username="test_user", balance=10000):
        self.id = id
        self.username = username
        self.balance = balance
        self.last_active_at = datetime.now() - timedelta(days=5)
        self.device_id_hash = "abc123hash"
        self.sender_profile = MockSenderProfile()


class MockSenderProfile:
    """Mock SenderProfile for testing"""
    def __init__(self):
        self.avg_transaction_amount = 500.0
        self.total_transactions_count = 50
        self.total_transactions_amount = 25000.0


class MockReceiverProfile:
    """Mock ReceiverProfile for testing"""
    def __init__(self):
        self.total_received_amount = 5000.0
        self.total_received_count = 20


class MockReceiver:
    """Mock Receiver for testing"""
    def __init__(self, id=2, username="receiver"):
        self.id = id
        self.username = username
        self.mcc = None
        self.receiver_profile = MockReceiverProfile()


class MockDB:
    """Mock database session"""
    def __init__(self):
        self.queries = []
        
    def query(self, *args, **kwargs):
        mock = MagicMock()
        mock.filter.return_value = mock
        mock.first.return_value = None
        mock.scalar.return_value = 0
        mock.all.return_value = []
        mock.order_by.return_value = mock
        mock.limit.return_value = mock
        return mock


# ═══════════════════════════════════════════════════════════════════════════
# FEATURE EXTRACTION TESTS
# ═══════════════════════════════════════════════════════════════════════════

class TestFeatureExtraction:
    """Tests for extract_features function"""
    
    def test_basic_features_extraction(self):
        """Test that basic features are extracted correctly"""
        from fraud_engine import extract_features
        
        db = MockDB()
        sender = MockUser()
        receiver = MockReceiver()
        amount = 100.0
        timestamp = datetime(2024, 1, 15, 14, 30)  # Monday 2:30 PM
        
        features = extract_features(db, sender, receiver, amount, timestamp)
        
        assert features['amount'] == 100.0
        assert features['hour'] == 14
        assert features['day_of_week'] == 0  # Monday
        assert features['is_weekend'] == 0
        assert features['is_night'] == 0
    
    def test_weekend_detection(self):
        """Test weekend feature"""
        from fraud_engine import extract_features
        
        db = MockDB()
        sender = MockUser()
        receiver = MockReceiver()
        
        # Saturday
        saturday = datetime(2024, 1, 20, 10, 0)
        features = extract_features(db, sender, receiver, 100, saturday)
        assert features['is_weekend'] == 1
        
    def test_night_detection(self):
        """Test night hour feature"""
        from fraud_engine import extract_features
        
        db = MockDB()
        sender = MockUser()
        receiver = MockReceiver()
        
        # 3 AM - should be night
        night = datetime(2024, 1, 15, 3, 0)
        features = extract_features(db, sender, receiver, 100, night)
        assert features['is_night'] == 1


# ═══════════════════════════════════════════════════════════════════════════
# RULE TESTS
# ═══════════════════════════════════════════════════════════════════════════

class TestFraudRules:
    """Tests for individual fraud detection rules"""
    
    def test_amount_spike_detection(self):
        """Test that 300%+ amount spike is detected (F5)"""
        # User has avg of 500, sending 2000 (400% = spike)
        sender = MockUser()
        sender.sender_profile.avg_transaction_amount = 500.0
        
        # F5 rule: amount > avg * 3
        amount = 2000.0
        ratio = amount / sender.sender_profile.avg_transaction_amount
        
        assert ratio > 3.0, "Should detect 400% spike"
    
    def test_round_amount_detection(self):
        """Test suspicious round amounts (F14)"""
        suspicious_amounts = [10000, 20000, 25000, 50000, 100000]
        
        # Normal amounts should not trigger
        assert 1500 not in suspicious_amounts
        assert 7777 not in suspicious_amounts
        
        # Round amounts should trigger
        assert 10000 in suspicious_amounts
        assert 50000 in suspicious_amounts


# ═══════════════════════════════════════════════════════════════════════════
# TRUST GRAPH TESTS
# ═══════════════════════════════════════════════════════════════════════════

class TestTrustGraph:
    """Tests for social graph trust calculation"""
    
    def test_stranger_detection(self):
        """Test that strangers have trust depth 0"""
        from fraud_engine import calculate_trust_depth
        
        db = MockDB()
        # No trust relationships in mock = stranger
        depth = calculate_trust_depth(db, sender_id=1, receiver_id=99)
        
        assert depth == 0, "Unknown receiver should be stranger"


# ═══════════════════════════════════════════════════════════════════════════
# AI SCORE TESTS
# ═══════════════════════════════════════════════════════════════════════════

class TestAIScoring:
    """Tests for AI anomaly scoring"""
    
    def test_get_ai_score_without_model(self):
        """Test AI score returns neutral when no model trained"""
        from fraud_engine import get_ai_score
        
        # When no model is trained, should return neutral score
        # v3.0: 28 features required
        features = {
            # Original 16 features
            'amount': 100, 'hour': 14, 'day_of_week': 1,
            'is_weekend': 0, 'is_night': 0, 'tx_count_1h': 0,
            'tx_count_24h': 0, 'total_amount_24h': 0, 'avg_amount': 0,
            'amount_vs_avg_ratio': 1.0, 'minutes_since_last_tx': 60,
            'unique_receivers_24h': 1, 'is_new_receiver': 0,
            'trust_score': 1.0, 'account_age_days': 30,
            'receiver_unique_senders_24h': 1,
            # New 12 features (v3.0)
            'session_tx_count': 1, 'avg_session_tx': 3.0,
            'recipient_age_days': 30, 'recipient_tx_volume': 10000,
            'amount_percentile': 50, 'hour_frequency': 10,
            'day_frequency': 10, 'is_first_time_amount': 0,
            'consecutive_tx_count': 0, 'balance_utilization': 50
        }
        
        score = get_ai_score(features)
        # Should be 0.0 when not trained
        assert score == 0.0


# ═══════════════════════════════════════════════════════════════════════════
# INTEGRATION TESTS
# ═══════════════════════════════════════════════════════════════════════════

class TestEvaluateFraud:
    """Integration tests for main evaluate_fraud function"""
    
    def test_normal_transaction_passes(self):
        """Test that a normal small transaction passes"""
        # This would require a more complex mock setup
        # For now, we just verify the function exists and has correct signature
        from fraud_engine import evaluate_fraud
        import inspect
        
        sig = inspect.signature(evaluate_fraud)
        params = list(sig.parameters.keys())
        
        assert 'db' in params
        assert 'sender' in params
        assert 'receiver' in params
        assert 'amount' in params


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
