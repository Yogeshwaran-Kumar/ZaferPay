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
    new_pin: str

class UserResponse(UserBase):
    id: int
    upi_id: str
    balance: float
    mcc: Optional[str] = None
    mobile_number: Optional[str] = None
    # We don't return hashed_password or sensitive fields
    
    class Config:
        from_attributes = True

class UserLookupResponse(UserResponse):
    pass

class ContactLookupRequest(BaseModel):
    phone_numbers: List[str]

class ContactMatch(BaseModel):
    phone_number: str
    upi_id: str
    username: str

class ContactLookupResponse(BaseModel):
    matches: List[ContactMatch]

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

class HomeAggregateResponse(BaseModel):
    user: UserResponse
    history: List[TransactionResponse]
    people: List[UserLookupResponse]
    merchants: List[UserLookupResponse]

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
