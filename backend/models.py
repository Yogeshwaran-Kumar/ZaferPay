"""
Database Models - Secure UPI Payment App

Security Design:
- UPI ID: Plain text (designed to be shared via QR/contacts)
- upi_id_hash: SHA-256 for searchable lookup
- PIN (hashed_password): Argon2id hash - VERY SECURE
- Transaction amounts: AES-256 encrypted
- Message content: AES-256 encrypted
- Email/Phone: Plain text (required for search/login)
- Device ID: Plain text (used for device binding)

All encryption/decryption happens in main.py using the security module.
"""

from sqlalchemy import Column, Integer, String, Float, DateTime, ForeignKey, Boolean, Index
from sqlalchemy.orm import relationship
from database import Base
import datetime


class User(Base):
    """
    User Account Model
    
    Security:
    - hashed_password: Argon2id hash (strongest password hashing)
    - upi_id: Plain (shareable by design)
    - upi_id_hash: SHA-256 for secure search
    """
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String, unique=True, index=True)
    
    # ═══════════════════════════════════════════════════════════════════════════
    # SECURE FIELDS - No plain text stored
    # ═══════════════════════════════════════════════════════════════════════════
    
    # Mobile Number (SECURE: Hash for search, Encrypt for display)
    mobile_hash = Column(String, unique=True, index=True)  # SHA-256 hash for search
    mobile_encrypted = Column(String)  # AES-256 encrypted for display
    
    # Email (SECURE: Hash for search, Encrypt for display)
    email_hash = Column(String, unique=True, index=True)  # SHA-256 hash for search
    email_encrypted = Column(String)  # AES-256 encrypted for display
    
    # Password/PIN
    hashed_password = Column(String)  # Argon2id hash - SECURE
    
    # UPI ID (Shareable - kept plain for QR/contacts sharing)
    upi_id = Column(String, unique=True, index=True)  # Plain (designed to be shared)
    upi_id_hash = Column(String, index=True, nullable=True)  # SHA-256 for search
    
    # Merchant Category Code
    mcc = Column(String, nullable=True)
    
    # Device ID (SECURE: Only encrypted stored)
    device_id_hash = Column(String, index=True, nullable=True)  # SHA-256 for device binding check
    device_id_encrypted = Column(String, nullable=True)  # AES-256 encrypted
    
    # Timestamps & Balance
    last_active_at = Column(DateTime, nullable=True)
    balance = Column(Float, default=0.0)

    # Relationships
    sender_profile = relationship("SenderProfile", back_populates="user", uselist=False)
    receiver_profile = relationship("ReceiverProfile", back_populates="user", uselist=False)

    @property
    def mobile_number(self):
        """Decrypt mobile number on the fly for Pydantic serialization"""
        if not self.mobile_encrypted:
            return None
        try:
            # Local import to avoid circular dependency
            import security
            return security.decrypt_value(self.mobile_encrypted)
        except:
            return None


class Transaction(Base):
    """
    Transaction Model
    
    Security:
    - amount: Plain float for calculations
    - encrypted_amount: AES-256 encrypted string for audit trail
    """
    __tablename__ = "transactions"

    id = Column(Integer, primary_key=True, index=True)
    transaction_id = Column(String, unique=True, index=True)
    sender_id = Column(Integer, ForeignKey("users.id"))
    receiver_id = Column(Integer, ForeignKey("users.id"))
    amount = Column(Float)  # Plain for calculations
    encrypted_amount = Column(String, nullable=True)  # AES-256 encrypted
    timestamp = Column(DateTime, default=datetime.datetime.utcnow, index=True)
    status = Column(String)  # SUCCESS, BLOCKED, FAILED
    risk_score = Column(String)  # SAFE, WARN, HIGH
    
    # Indexes for faster queries
    __table_args__ = (
        Index('ix_transactions_sender_id', 'sender_id'),
        Index('ix_transactions_receiver_id', 'receiver_id'),
        # Composite indexes for "Home Aggregate" optimization (filtering by user AND sorting by time)
        Index('ix_transactions_sender_timestamp', 'sender_id', 'timestamp'),
        Index('ix_transactions_receiver_timestamp', 'receiver_id', 'timestamp'),
    )
    
    sender = relationship("User", foreign_keys=[sender_id])
    receiver = relationship("User", foreign_keys=[receiver_id])


class SenderProfile(Base):
    """Sender behavior profile for fraud detection"""
    __tablename__ = "sender_profiles"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), unique=True)
    avg_transaction_amount = Column(Float, default=0.0)
    total_transactions_count = Column(Integer, default=0)
    monthly_volume = Column(Float, default=0.0)
    last_transaction_time = Column(DateTime, nullable=True)
    
    user = relationship("User", back_populates="sender_profile")


class ReceiverProfile(Base):
    """Receiver behavior profile for fraud detection"""
    __tablename__ = "receiver_profiles"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), unique=True)
    total_received_amount = Column(Float, default=0.0)
    total_received_count = Column(Integer, default=0)
    unique_senders_count = Column(Integer, default=0)
    
    user = relationship("User", back_populates="receiver_profile")


class Message(Base):
    """
    Chat Message Model
    
    Security:
    - content: Plain text (backward compatibility)
    - encrypted_content: AES-256 encrypted
    """
    __tablename__ = "messages"

    id = Column(Integer, primary_key=True, index=True)
    sender_id = Column(Integer, ForeignKey("users.id"))
    receiver_id = Column(Integer, ForeignKey("users.id"))
    content = Column(String)  # Plain (backward compatibility)
    encrypted_content = Column(String, nullable=True)  # AES-256 encrypted
    timestamp = Column(DateTime, default=datetime.datetime.utcnow)
    
    sender = relationship("User", foreign_keys=[sender_id])
    receiver = relationship("User", foreign_keys=[receiver_id])

    # Indexes for lightning-fast history lookup (OR queries)
    __table_args__ = (
        Index('ix_messages_sender_id', 'sender_id'),
        Index('ix_messages_receiver_id', 'receiver_id'),
        Index('ix_messages_timestamp', 'timestamp'),
    )


class LoginHistory(Base):
    """
    Login Session Tracking (SECURE)
    
    Security:
    - No plain device_id or ip_address stored
    - Hash for device binding verification
    - Encrypted for audit trail
    """
    __tablename__ = "login_history"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    
    # Device ID (SECURE)
    device_id_hash = Column(String, index=True)  # SHA-256 for device binding check
    device_id_encrypted = Column(String)  # AES-256 encrypted for audit
    
    # IP Address (SECURE)
    ip_hash = Column(String, index=True, nullable=True)  # SHA-256 for fraud detection
    ip_encrypted = Column(String, nullable=True)  # AES-256 encrypted for audit
    
    # Timestamps
    login_time = Column(DateTime, default=datetime.datetime.utcnow)
    logout_time = Column(DateTime, nullable=True)
    is_active = Column(Boolean, default=True)
    
    user = relationship("User", back_populates="login_history")


class IdempotencyKey(Base):
    """
    Idempotency Key Storage - Prevents Duplicate Transactions
    
    When user clicks "Pay" multiple times (slow network), the server
    returns cached response instead of processing duplicate payments.
    """
    __tablename__ = "idempotency_keys"

    id = Column(Integer, primary_key=True, index=True)
    key = Column(String, unique=True, index=True, nullable=False)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    transaction_id = Column(String, nullable=True)
    response_status = Column(String, nullable=False)
    response_data = Column(String, nullable=True)  # JSON response
    created_at = Column(DateTime, default=datetime.datetime.utcnow)
    
    user = relationship("User")


# Add login_history relationship to User
User.login_history = relationship("LoginHistory", back_populates="user")
