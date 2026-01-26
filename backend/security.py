"""
Security Module - AES-256 Encryption & Hashing

This module provides cryptographic functions for the Zero-Trust Vault architecture.
All sensitive data is encrypted before storage and decrypted only when needed.

Security Stack:
- AES-256 (Fernet) for reversible encryption (amounts, messages, UPI IDs)
- SHA-256 for searchable hashes (UPI ID lookup)
- Master Key loaded from environment (never stored in code or database)
"""

import os
import hashlib
from typing import Union, Optional
from cryptography.fernet import Fernet, InvalidToken
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# ═══════════════════════════════════════════════════════════════════════════
# MASTER KEY MANAGEMENT
# ═══════════════════════════════════════════════════════════════════════════

_MASTER_KEY = os.getenv("MASTER_KEY")
_HASH_SALT = os.getenv("HASH_SALT", "fallback-salt-change-in-prod")

if not _MASTER_KEY:
    print("⚠️  WARNING: MASTER_KEY not found in environment.")
    print("⚠️  Generating temporary key for development only.")
    print("⚠️  Add MASTER_KEY to .env file for production!")
    # Generate a temporary key for development
    _MASTER_KEY = Fernet.generate_key().decode()

if "fallback-salt" in _HASH_SALT:
     print("⚠️  WARNING: HASH_SALT not found or default. Rainbow table attacks possible.")

# Initialize Fernet cipher
try:
    _cipher = Fernet(_MASTER_KEY.encode() if isinstance(_MASTER_KEY, str) else _MASTER_KEY)
except Exception as e:
    print(f"⚠️  Invalid MASTER_KEY format: {e}")
    print("⚠️  Generating temporary key.")
    _cipher = Fernet(Fernet.generate_key())

# ═══════════════════════════════════════════════════════════════════════════
# ENCRYPTION FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════

def encrypt_value(value: Union[str, int, float]) -> str:
    """
    Encrypt a value using AES-256 (Fernet).
    
    Args:
        value: String, int, or float to encrypt
        
    Returns:
        Encrypted string (Fernet token)
        
    Example:
        >>> encrypt_value(500.00)
        'gAAAAABk...'
    """
    if value is None:
        return None
    
    # Convert to string for encryption
    str_value = str(value)
    encrypted = _cipher.encrypt(str_value.encode())
    return encrypted.decode()


def decrypt_value(encrypted: str, value_type: type = str) -> Optional[Union[str, int, float]]:
    """
    Decrypt a Fernet-encrypted value.
    
    Args:
        encrypted: Fernet token string
        value_type: Expected type (str, int, or float) for conversion
        
    Returns:
        Decrypted value in the requested type, or None if decryption fails
        
    Example:
        >>> decrypt_value('gAAAAABk...', float)
        500.0
    """
    if encrypted is None:
        return None
    
    # Check if value is actually encrypted (Fernet tokens start with 'gAAAAA')
    if not is_encrypted(encrypted):
        # Return as-is (backward compatibility for unencrypted data)
        try:
            if value_type == float:
                return float(encrypted)
            elif value_type == int:
                return int(encrypted)
            return str(encrypted)
        except (ValueError, TypeError):
            return encrypted
    
    try:
        decrypted_bytes = _cipher.decrypt(encrypted.encode())
        decrypted_str = decrypted_bytes.decode()
        
        # Convert to requested type
        if value_type == float:
            return float(decrypted_str)
        elif value_type == int:
            return int(decrypted_str)
        return decrypted_str
        
    except InvalidToken:
        print(f"⚠️  Decryption failed - invalid token")
        return None
    except Exception as e:
        print(f"⚠️  Decryption error: {e}")
        return None


def is_encrypted(value: str) -> bool:
    """
    Check if a value is Fernet-encrypted.
    
    Fernet tokens always start with 'gAAAAA' (base64 encoded header).
    
    Args:
        value: String to check
        
    Returns:
        True if value appears to be encrypted
    """
    if value is None or not isinstance(value, str):
        return False
    return value.startswith('gAAAAA')


# ═══════════════════════════════════════════════════════════════════════════
# HASHING FUNCTIONS (For Searchable Fields)
# ═══════════════════════════════════════════════════════════════════════════

def hash_value(value: str) -> str:
    """
    Create a SHA-256 hash of a value for searchable storage.
    
    This is used for fields like UPI ID where we need to search
    but also want to hide the actual value in the database.
    
    Args:
        value: String to hash
        
    Returns:
        Hex-encoded SHA-256 hash
        
    Example:
        >>> hash_value("user@mockbank")
        'a1b2c3d4e5f6...'
    """
    if value is None:
        return None
    
    import hmac
    
    # Normalize: lowercase and strip whitespace
    normalized = value.lower().strip()
    
    # Create HMAC-SHA256 hash (Salted Hash)
    # Using HMAC prevents length extension attacks and binds hash to the salt
    hash_obj = hmac.new(
        _HASH_SALT.encode(),
        normalized.encode(),
        hashlib.sha256
    )
    return hash_obj.hexdigest()


# ═══════════════════════════════════════════════════════════════════════════
# UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════

def encrypt_balance(balance: float) -> str:
    """Encrypt a balance value."""
    return encrypt_value(str(balance))


def decrypt_balance(encrypted: str) -> float:
    """Decrypt a balance value."""
    result = decrypt_value(encrypted, float)
    return result if result is not None else 0.0


def generate_master_key() -> str:
    """
    Generate a new Fernet master key.
    
    Use this to create a key for production:
    ```
    python -c "from security import generate_master_key; print(generate_master_key())"
    ```
    
    IMPORTANT: Store this key securely and add to .env file.
    """
    return Fernet.generate_key().decode()


# ═══════════════════════════════════════════════════════════════════════════
# TEST FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    print("Security Module Test")
    print("=" * 50)
    
    # Test encryption/decryption
    test_amount = 500.50
    encrypted = encrypt_value(test_amount)
    decrypted = decrypt_value(encrypted, float)
    print(f"Amount: {test_amount} -> Encrypted: {encrypted[:30]}... -> Decrypted: {decrypted}")
    print(f"Match: {test_amount == decrypted}")
    
    # Test hashing
    test_upi = "user@mockbank"
    hashed = hash_value(test_upi)
    print(f"\nUPI: {test_upi} -> Hash: {hashed[:30]}...")
    
    # Test backward compatibility
    plain_value = "100.00"
    print(f"\nPlain value: {plain_value} -> Is Encrypted: {is_encrypted(plain_value)}")
    print(f"Decrypt plain: {decrypt_value(plain_value, float)}")
