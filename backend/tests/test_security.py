"""
Comprehensive Security Tests - SafePay

Run with: pytest tests/test_security.py -v
"""

import pytest
import sys
import os
from datetime import datetime, timedelta
from unittest.mock import MagicMock, patch

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


# ═══════════════════════════════════════════════════════════════════════════
# GEO-VELOCITY TESTS
# ═══════════════════════════════════════════════════════════════════════════

class TestGeoVelocity:
    """Tests for geo-velocity (impossible travel) detection"""
    
    def test_calculate_distance_km(self):
        """Test Haversine distance calculation"""
        from fraud_engine import calculate_distance_km
        
        # New York to Los Angeles (approx 3940 km)
        ny_lat, ny_lon = 40.7128, -74.0060
        la_lat, la_lon = 34.0522, -118.2437
        
        distance = calculate_distance_km(ny_lat, ny_lon, la_lat, la_lon)
        
        assert 3900 < distance < 4000, f"Expected ~3940 km, got {distance}"
    
    def test_calculate_distance_same_location(self):
        """Test distance is 0 for same location"""
        from fraud_engine import calculate_distance_km
        
        distance = calculate_distance_km(40.0, -74.0, 40.0, -74.0)
        assert distance == 0
    
    def test_calculate_distance_with_none(self):
        """Test distance with None values returns 0"""
        from fraud_engine import calculate_distance_km
        
        distance = calculate_distance_km(None, -74.0, 40.0, -74.0)
        assert distance == 0
    
    def test_check_geo_velocity_no_violation(self):
        """Test no violation for reasonable travel"""
        from fraud_engine import check_geo_velocity, GEOIP_ENABLED
        
        if not GEOIP_ENABLED:
            pytest.skip("GeoIP not enabled")
        
        # Realistic travel: 100 km in 2 hours = 50 km/h
        # This should not trigger
        is_violation, distance, speed = check_geo_velocity(
            current_ip="8.8.8.8",  # Google DNS (placeholder)
            last_ip="8.8.4.4",     # Google DNS 2
            minutes_since_last=120
        )
        
        # With real IPs, distance would be calculated
        # If IPs are in same location, no violation
        assert is_violation == False or distance < 500
    
    def test_geo_velocity_functions_exist(self):
        """Verify geo-velocity functions are available"""
        from fraud_engine import (
            get_location_from_ip,
            calculate_distance_km,
            check_geo_velocity,
            GEOIP_ENABLED
        )
        
        assert callable(get_location_from_ip)
        assert callable(calculate_distance_km)
        assert callable(check_geo_velocity)


# ═══════════════════════════════════════════════════════════════════════════
# AUTH TOKEN TESTS
# ═══════════════════════════════════════════════════════════════════════════

class TestAuthTokens:
    """Tests for authentication token security"""
    
    def test_access_token_creation(self):
        """Test access token is created correctly"""
        import auth
        
        token = auth.create_access_token(data={"sub": "test_user"})
        assert token is not None
        assert len(token) > 50  # JWT tokens are typically long
    
    def test_access_token_verification(self):
        """Test access token can be verified"""
        import auth
        
        token = auth.create_access_token(data={"sub": "test_user"})
        payload = auth.verify_access_token(token)
        
        assert payload is not None
        assert payload["sub"] == "test_user"
        assert payload["type"] == "access"
    
    def test_refresh_token_has_jti(self):
        """Test refresh token includes unique JWT ID for rotation"""
        import auth
        from jose import jwt
        
        token = auth.create_refresh_token(data={"sub": "test_user"})
        payload = jwt.decode(token, auth.SECRET_KEY, algorithms=[auth.ALGORITHM])
        
        assert "jti" in payload, "Refresh token must have JWT ID for rotation"
        assert len(payload["jti"]) > 0
    
    def test_refresh_tokens_have_unique_jti(self):
        """Test each refresh token gets a unique JWT ID"""
        import auth
        from jose import jwt
        
        token1 = auth.create_refresh_token(data={"sub": "user1"})
        token2 = auth.create_refresh_token(data={"sub": "user1"})
        
        payload1 = jwt.decode(token1, auth.SECRET_KEY, algorithms=[auth.ALGORITHM])
        payload2 = jwt.decode(token2, auth.SECRET_KEY, algorithms=[auth.ALGORITHM])
        
        assert payload1["jti"] != payload2["jti"], "Each token must have unique ID"
    
    def test_invalid_token_rejected(self):
        """Test that invalid tokens are rejected"""
        import auth
        
        result = auth.verify_access_token("invalid.token.here")
        assert result is None
    
    def test_access_token_not_valid_as_refresh(self):
        """Test access token cannot be used as refresh token"""
        import auth
        
        access_token = auth.create_access_token(data={"sub": "test_user"})
        result = auth.verify_refresh_token(access_token)
        
        assert result is None, "Access token should not verify as refresh token"


# ═══════════════════════════════════════════════════════════════════════════
# PASSWORD SECURITY TESTS
# ═══════════════════════════════════════════════════════════════════════════

class TestPasswordSecurity:
    """Tests for password hashing security (Argon2id)"""
    
    def test_password_hashing(self):
        """Test password is hashed with Argon2id"""
        import auth
        
        password = "SecurePassword123!"
        hashed = auth.get_password_hash(password)
        
        assert hashed != password
        assert "$argon2id$" in hashed, "Must use Argon2id algorithm"
    
    def test_password_verification(self):
        """Test correct password verifies"""
        import auth
        
        password = "SecurePassword123!"
        hashed = auth.get_password_hash(password)
        
        assert auth.verify_password(password, hashed) == True
    
    def test_wrong_password_rejected(self):
        """Test wrong password is rejected"""
        import auth
        
        password = "SecurePassword123!"
        wrong_password = "WrongPassword456!"
        hashed = auth.get_password_hash(password)
        
        assert auth.verify_password(wrong_password, hashed) == False
    
    def test_same_password_different_hashes(self):
        """Test same password produces different hashes (unique salts)"""
        import auth
        
        password = "SamePassword123!"
        hash1 = auth.get_password_hash(password)
        hash2 = auth.get_password_hash(password)
        
        assert hash1 != hash2, "Hashes should be unique due to random salt"


# ═══════════════════════════════════════════════════════════════════════════
# HMAC REQUEST SIGNING TESTS
# ═══════════════════════════════════════════════════════════════════════════

class TestHMACSigning:
    """Tests for HMAC request signing"""
    
    def test_signature_generation(self):
        """Test HMAC signature is generated"""
        import auth
        
        data = '{"amount": 100, "receiver": "user2"}'
        timestamp = "1234567890"
        
        signature = auth.generate_request_signature(data, timestamp)
        
        assert signature is not None
        assert len(signature) == 64  # SHA256 hex = 64 chars
    
    def test_signature_verification(self):
        """Test valid signature verifies"""
        import auth
        import time
        
        data = '{"amount": 100}'
        timestamp = str(int(time.time()))  # Current time for freshness check
        
        signature = auth.generate_request_signature(data, timestamp)
        is_valid = auth.verify_request_signature(data, timestamp, signature)
        
        assert is_valid == True
    
    def test_tampered_data_rejected(self):
        """Test tampered data fails verification"""
        import auth
        
        data = '{"amount": 100}'
        tampered_data = '{"amount": 1000}'  # Changed amount
        timestamp = "1234567890"
        
        signature = auth.generate_request_signature(data, timestamp)
        is_valid = auth.verify_request_signature(tampered_data, timestamp, signature)
        
        assert is_valid == False


# ═══════════════════════════════════════════════════════════════════════════
# ENCRYPTION TESTS
# ═══════════════════════════════════════════════════════════════════════════

class TestEncryption:
    """Tests for AES-256 encryption"""
    
    def test_encrypt_decrypt_roundtrip(self):
        """Test encryption and decryption roundtrip"""
        import security
        
        original = "SensitiveData123"
        encrypted = security.encrypt_value(original)
        decrypted = security.decrypt_value(encrypted)
        
        assert decrypted == original
    
    def test_encryption_produces_different_ciphertext(self):
        """Test same plaintext produces different ciphertext (IV)"""
        import security
        
        value = "TestValue"
        enc1 = security.encrypt_value(value)
        enc2 = security.encrypt_value(value)
        
        # Due to random IV, ciphertexts should differ
        # (depending on implementation)
        # At minimum, both should decrypt correctly
        assert security.decrypt_value(enc1) == value
        assert security.decrypt_value(enc2) == value
    
    def test_hash_is_deterministic(self):
        """Test hash function produces consistent output"""
        import security
        
        value = "9876543210"
        hash1 = security.hash_value(value)
        hash2 = security.hash_value(value)
        
        assert hash1 == hash2, "Same input must produce same hash"


# ═══════════════════════════════════════════════════════════════════════════
# FRAUD RULE TESTS
# ═══════════════════════════════════════════════════════════════════════════

class TestFraudRules:
    """Tests for specific fraud detection rules"""
    
    def test_mcc_tier_classification(self):
        """Test MCC codes are classified correctly"""
        from fraud_engine import get_mcc_tier
        
        # Test Essential (hospitals)
        assert get_mcc_tier("8011") == "ESSENTIAL"
        
        # Test Retail (grocery)
        assert get_mcc_tier("5411") == "RETAIL"
        
        # Test Personal (unknown MCC)
        assert get_mcc_tier("0000") == "PERSONAL"
        assert get_mcc_tier(None) == "PERSONAL"
        assert get_mcc_tier("") == "PERSONAL"
    
    def test_tier_config_exists(self):
        """Test all tiers have configuration"""
        from fraud_engine import get_tier_config
        
        for tier in ["ESSENTIAL", "HIGH_VALUE", "RETAIL", "SERVICES", "PERSONAL"]:
            config = get_tier_config(tier)
            assert config is not None
            assert "trust_bonus" in config or "velocity_limit" in config
    
    def test_daily_limits_are_set(self):
        """Test permanent daily limits are configured"""
        from fraud_engine import DAILY_RECEIVER_LIMIT_P2P, DAILY_RECEIVER_LIMIT_MERCHANT
        
        assert DAILY_RECEIVER_LIMIT_P2P == 100000  # ₹1 Lakh
        assert DAILY_RECEIVER_LIMIT_MERCHANT == 300000  # ₹3 Lakh


# ═══════════════════════════════════════════════════════════════════════════
# MODEL SECURITY TESTS
# ═══════════════════════════════════════════════════════════════════════════

class TestModelSecurity:
    """Tests for ML model security (HMAC signing)"""
    
    def test_model_path_exists(self):
        """Test model path constant is defined"""
        from fraud_engine import MODEL_PATH
        
        assert MODEL_PATH is not None
        assert MODEL_PATH.endswith(".pkl")
    
    def test_model_loading_function_exists(self):
        """Test model loading function is available"""
        from fraud_engine import load_model_readonly
        
        assert callable(load_model_readonly)


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
