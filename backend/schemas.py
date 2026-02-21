from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime

# ═══════════════════════════════════════════════════════════════════════════
# AUTH & TOKEN SCHEMAS
# ═══════════════════════════════════════════════════════════════════════════

class Token(BaseModel):
    access_token: str
    refresh_token: Optional[str] = None
    token_type: str
    expires_in: int

class TokenData(BaseModel):
    username: Optional[str] = None

class MobileCheckRequest(BaseModel):
    mobile_number: str

class MobileCheckResponse(BaseModel):
    exists: bool
    status: str
    upi_id: Optional[str] = None
    has_device_conflict: bool = False

# ═══════════════════════════════════════════════════════════════════════════
# USER SCHEMAS
# ═══════════════════════════════════════════════════════════════════════════

class UserBase(BaseModel):
    username: str

class UserRegister(UserBase):
    mobile_number: Optional[str] = None
    email: Optional[str] = None
    password: str

class PinSetRequest(BaseModel):
    mobile_number: str
    pin: str
    upi_id: Optional[str] = None

class ChangePinRequest(BaseModel):
    current_pin: str
    new_pin: str

class UserResponse(UserBase):
    id: int
    upi_id: str
    balance: float
    mcc: Optional[str] = None
    mobile_number: Optional[str] = None
    bank_name: Optional[str] = None
    # We don't return hashed_password or sensitive fields
    
    class Config:
        from_attributes = True

class UserLookupResponse(UserResponse):
    unread_count: int = 0

class PublicUserResponse(BaseModel):
    username: str
    upi_id: str
    mcc: Optional[str] = None


class ContactLookupRequest(BaseModel):
    phone_numbers: List[str]
    
class ContactMatch(BaseModel):
    phone_number: str
    upi_id: str
    username: str

class ContactLookupResponse(BaseModel):
    matches: List[ContactMatch]

class FCMTokenUpdate(BaseModel):
    fcm_token: str

# ═══════════════════════════════════════════════════════════════════════════
# BANK ACCOUNT SCHEMAS
# ═══════════════════════════════════════════════════════════════════════════

class BankAccountResponse(BaseModel):
    bank_name: str
    upi_id: str
    
    class Config:
        from_attributes = True

class BankNameResponse(BaseModel):
    """Level 1: Just the bank name (click to see details)"""
    bank_name: str
    account_count: int = 0

class BankDetailResponse(BaseModel):
    """Level 2: Details shown when you click a bank name"""
    upi_id: str
    has_pin: bool  # True if PIN is set, False otherwise
    username: str

# ═══════════════════════════════════════════════════════════════════════════
# TRANSACTION SCHEMAS
# ═══════════════════════════════════════════════════════════════════════════

class TransactionCreate(BaseModel):
    receiver_upi_id: str
    amount: float
    pin: str
    idempotency_key: Optional[str] = None
    receiver_mcc: Optional[str] = None
    note: Optional[str] = None
    skip_fraud_check: bool = False  # Skip AI fraud check if user already acknowledged risk
    acknowledged_risk: Optional[str] = None  # 'WARN' or 'HIGH' if user proceeded despite warning
    request_id: Optional[int] = None  # Link to a payment request if this is a payment for one
    # v5.0: Scam telemetry fields (sent by mobile app)
    payment_source: Optional[str] = None  # 'qr_scan', 'deep_link', 'manual_entry', 'contact_list'
    is_screen_sharing: bool = False  # True if remote-access app (AnyDesk/TeamViewer) detected

class TransactionResponse(BaseModel):
    transaction_id: str
    sender_upi_id: str
    receiver_upi_id: str
    sender_name: str
    receiver_name: str
    amount: float
    status: str
    risk_score: str
    timestamp: datetime
    sender_mcc: Optional[str] = None
    receiver_mcc: Optional[str] = None
    note: Optional[str] = None

    class Config:
        from_attributes = True

# Pre-PIN Risk Analysis (runs fraud engine without creating transaction)
class TransactionAnalyze(BaseModel):
    receiver_upi_id: str
    amount: float
    receiver_mcc: Optional[str] = None
    note: Optional[str] = None
    is_contact: bool = False
    # v5.0: Scam telemetry fields (sent by mobile app)
    payment_source: Optional[str] = None  # 'qr_scan', 'deep_link', 'manual_entry', 'contact_list'
    is_screen_sharing: bool = False  # True if remote-access app detected

class TransactionAnalyzeResponse(BaseModel):
    risk_score: str  # 'SAFE', 'WARN', 'HIGH'
    risk_reason: Optional[str] = None
    is_blocked: bool = False
    receiver_name: Optional[str] = None
    receiver_exists: bool = True
    is_contact: bool = False
    is_bypassable: bool = True
    detail: Optional[dict] = None


# ═══════════════════════════════════════════════════════════════════════════
# HISTORY SCHEMAS
# ═══════════════════════════════════════════════════════════════════════════

class LoginHistoryResponse(BaseModel):
    login_time: datetime
    logout_time: Optional[datetime]
    is_active: bool
    
    class Config:
        from_attributes = True

class DeviceLoginStats(BaseModel):
    device_name: str # "Device A", "Device B" (Derived from hash/order)
    login_count: int
    timings: List[datetime]

class DeviceSummaryResponse(BaseModel):
    total_new_devices: int
    devices: List[DeviceLoginStats]

# ═══════════════════════════════════════════════════════════════════════════
# MESSAGE SCHEMAS
# ═══════════════════════════════════════════════════════════════════════════

class MessageCreate(BaseModel):
    receiver_upi_id: str
    content: str
    
class MessageResponse(BaseModel):
    id: int
    sender_upi_id: str
    receiver_upi_id: str
    content: str
    timestamp: datetime
    
    class Config:
        from_attributes = True



# ═══════════════════════════════════════════════════════════════════════════
# FRAUD REPORTING SCHEMAS
# ═══════════════════════════════════════════════════════════════════════════

class FraudReportRequest(BaseModel):
    """User reports a transaction as fraudulent"""
    transaction_id: str
    reason: str  # "not_me", "wrong_amount", "unknown_receiver", "other"
    description: Optional[str] = None  # Optional details

class FraudReportResponse(BaseModel):
    """Response after fraud report submission"""
    success: bool
    message: str
    report_id: Optional[int] = None

# ═══════════════════════════════════════════════════════════════════════════
# PAYMENT REQUEST SCHEMAS
# ═══════════════════════════════════════════════════════════════════════════

class PaymentRequestCreate(BaseModel):
    payer_upi_id: str  # Who you are asking money from
    amount: float
    reason: str  # "wrongly_sent", "wrong_amount", "other"
    description: Optional[str] = None
    original_transaction_id: Optional[str] = None  # Link to originating transaction

class PaymentRequestResponse(BaseModel):
    id: int
    requester_id: int
    requester_upi_id: str
    payer_upi_id: str
    requester_name: Optional[str] = None
    payer_name: Optional[str] = None
    amount: float
    status: str  # pending, paid, rejected, cancelled
    reason: str
    description: Optional[str] = None
    original_transaction_id: Optional[str] = None
    timestamp: datetime
    cancelled_by: Optional[str] = None

    class Config:
        from_attributes = True


class HomeAggregateResponse(BaseModel):
    user: UserResponse
    history: List[TransactionResponse]
    people: List[UserLookupResponse]
    merchants: List[UserLookupResponse]
    pending_requests: List[PaymentRequestResponse] = []
    total_unread: int = 0


# ═══════════════════════════════════════════════════════════════════════════
# NOTIFICATION SCHEMAS
# ═══════════════════════════════════════════════════════════════════════════

class NotificationResponse(BaseModel):
    id: int
    title: str
    message: str
    type: str
    is_read: bool
    timestamp: datetime

    class Config:
        from_attributes = True

class NotificationReadRequest(BaseModel):
    notification_id: int


# ═══════════════════════════════════════════════════════════════════════════
# ADMIN SCHEMAS
# ═══════════════════════════════════════════════════════════════════════════

class FraudConfirmationRequest(BaseModel):
    report_id: int
    is_fraud: bool

class TransactionAuditResponse(BaseModel):
    transaction_id: str
    ip_address: Optional[str] = None
    decrypted_at: datetime


# ═══════════════════════════════════════════════════════════════════════════
# CONTACT SYNC SCHEMAS
# ═══════════════════════════════════════════════════════════════════════════

class ContactSyncRequest(BaseModel):
    contacts: List[str] # List of mobile numbers (raw or normalized)

class ContactSyncResponse(BaseModel):
    synced_count: int
    new_trust_links: int
    message: str

# ═══════════════════════════════════════════════════════════════════════════
# END OF FILE
# ═══════════════════════════════════════════════════════════════════════════
