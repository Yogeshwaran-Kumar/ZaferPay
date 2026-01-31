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
    
    # Merchant Category Code (MCC)
    mcc = Column(String, nullable=True)
    
    # Device ID (SECURE: Only encrypted stored)
    device_id_hash = Column(String, index=True, nullable=True)  # SHA-256 for device binding check
    device_id_encrypted = Column(String, nullable=True)  # AES-256 encrypted
    
    # Timestamps & Balance
    last_active_at = Column(DateTime, nullable=True)
    balance = Column(Float, default=0.0)  # Plain for fast calculations
    encrypted_balance = Column(String, nullable=True)  # AES-256 encrypted for audit
    
    # New: Total Device Count (Summary)
    total_device_count = Column(Integer, default=0)

    # Relationships
    sender_profile = relationship("SenderProfile", back_populates="user", uselist=False)
    receiver_profile = relationship("ReceiverProfile", back_populates="user", uselist=False)
    login_history = relationship("LoginHistory", back_populates="user")
    # trusted_devices relationship removed to avoid AmbiguousForeignKeysError (Logic uses direct queries)

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
    
    @property
    def secure_balance(self):
        """
        Get balance from encrypted field if available, else from plain field.
        This provides backward compatibility while ensuring new data is encrypted.
        """
        if self.encrypted_balance:
            try:
                import security
                decrypted = security.decrypt_value(self.encrypted_balance, float)
                if decrypted is not None:
                    return decrypted
            except:
                pass
        return self.balance
    
    def update_balance(self, new_balance: float):
        """
        Update balance in both plain (for fast queries) and encrypted (for security) fields.
        This is the ONLY method that should be used to modify balance.
        """
        import security
        self.balance = new_balance
        self.encrypted_balance = security.encrypt_value(str(new_balance))



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
    timestamp = Column(DateTime, default=datetime.datetime.now, index=True)
    status = Column(String)  # SUCCESS, BLOCKED, FAILED
    risk_score = Column(String)  # SAFE, WARN, HIGH
    
    # Additional Context for Fraud detection
    receiver_mcc = Column(String, nullable=True)
    note = Column(String, nullable=True)  # Payment Note (e.g. "Rent")
    
    # IP Tracking for Geo-Velocity Detection (F29)
    ip_hash = Column(String, nullable=True)  # HMAC-SHA256 hash for lookup
    ip_encrypted = Column(String, nullable=True)  # AES-256 encrypted for audit
    
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
    total_transactions_amount = Column(Float, default=0.0)
    monthly_volume = Column(Float, default=0.0)
    last_transaction_time = Column(DateTime, nullable=True)

    # ═══════════════════════════════════════════════════════════════════════════
    # ADAPTIVE LEARNING FIELDS (The "Memory")
    # ═══════════════════════════════════════════════════════════════════════════
    # The learned safe limit for this user (Starts at regular rule 5000)
    personal_trust_limit = Column(Float, default=5000.0)
    
    # How many times consistently they verified a high-value tx?
    override_streak_count = Column(Integer, default=0)
    
    # What was the last amount they verified? (To ensure consistency)
    last_override_amount = Column(Float, default=0.0)
    
    user = relationship("User", back_populates="sender_profile")


class ReceiverProfile(Base):
    """Receiver behavior profile for fraud detection"""
    __tablename__ = "receiver_profiles"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), unique=True)
    total_received_amount = Column(Float, default=0.0)
    total_received_count = Column(Integer, default=0)
    unique_senders_count = Column(Integer, default=0)
    last_received_time = Column(DateTime, nullable=True)
    
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
    timestamp = Column(DateTime, default=datetime.datetime.now)
    
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
    login_time = Column(DateTime, default=datetime.datetime.now)
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
    created_at = Column(DateTime, default=datetime.datetime.now)
    
    user = relationship("User")


class DeviceProfile(Base):
    """
    Authorized Devices & Usage Stats (The "Summary" Table)
    Stores the RUNNING COUNT of logins for each unique device.
    """
    __tablename__ = "device_profiles"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    device_id_hash = Column(String, index=True, nullable=False)
    device_name = Column(String) # e.g., "Device A", "Device B"
    
    # The Counter (What the user wants to see)
    login_count = Column(Integer, default=1)
    last_login_time = Column(DateTime, default=datetime.datetime.now)
    
    # Relationship
    user = relationship("User", backref="device_profiles") # Fixed back_populates/backref mismatch


# ═══════════════════════════════════════════════════════════════════════════
# NEW AI SECURITY TABLES (Phase 1)
# ═══════════════════════════════════════════════════════════════════════════

class FraudEvent(Base):
    """
    The Memory of the Brain.
    Stores every suspicious event to train the AI (scikit-learn).
    """
    __tablename__ = "fraud_events"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    transaction_id = Column(String, nullable=True)
    
    amount = Column(Float)
    ai_score = Column(Float) # The raw anomaly score (-1.0 to 1.0)
    rule_violation = Column(String) # Which rule failed? (e.g., "F1_VELOCITY")
    
    # The "Truth" Label (Did we block it? Was it actually fraud?)
    is_blocked = Column(Boolean, default=False)
    is_confirmed_fraud = Column(Boolean, nullable=True) # Manual feedback loop
    
    timestamp = Column(DateTime, default=datetime.datetime.now)
    
    user = relationship("User")


class UserTrustGraph(Base):
    """
    The User Trust Graph (Social Graph).
    Tracks who trusts whom. If A pays B often, B is "Trusted" by A.
    Formerly known as 'TrustedDevice'.
    """
    __tablename__ = "user_trust_graph"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id")) # The Payer
    trusted_user_id = Column(Integer, ForeignKey("users.id")) # The Payee
    
    trust_score = Column(Float, default=1.0) # Increases with successful txns
    last_interaction_at = Column(DateTime, default=datetime.datetime.now)
    
    user = relationship("User", foreign_keys=[user_id])
    trusted_user = relationship("User", foreign_keys=[trusted_user_id])


class RevokedToken(Base):
    """
    Revoked Tokens Table for Refresh Token Rotation
    
    Security: When a refresh token is used, it's revoked and a new one is issued.
    This prevents token replay attacks - if attacker steals a refresh token,
    it becomes invalid after single use.
    """
    __tablename__ = "revoked_tokens"

    id = Column(Integer, primary_key=True, index=True)
    token_jti = Column(String, unique=True, index=True)  # JWT ID (jti claim)
    user_id = Column(Integer, ForeignKey("users.id"))
    revoked_at = Column(DateTime, default=datetime.datetime.now)
    expires_at = Column(DateTime)  # For cleanup of old entries
    
    user = relationship("User")


class UserFraudReport(Base):
    """
    User Fraud Reports - REAL human-labeled fraud data for AI training
    
    This is GOLD for AI learning:
    - Users report transactions they didn't authorize
    - These become confirmed fraud examples
    - AI learns to detect similar patterns
    
    This is what makes the difference between:
    - Guessing what's fraud (auto-blocked)
    - KNOWING what's fraud (user-reported)
    """
    __tablename__ = "user_fraud_reports"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), index=True)  # Who reported
    transaction_id = Column(String, index=True)  # Which transaction
    
    # Report details
    reason = Column(String)  # "not_me", "wrong_amount", "unknown_receiver", "other"
    description = Column(String, nullable=True)  # Optional user description
    
    # Status
    status = Column(String, default="pending")  # "pending", "confirmed", "rejected"
    reported_at = Column(DateTime, default=datetime.datetime.now)
    reviewed_at = Column(DateTime, nullable=True)
    
    # For AI training
    is_confirmed_fraud = Column(Boolean, default=True)  # True = confirmed fraud for training
    
    user = relationship("User")
