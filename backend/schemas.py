from pydantic import BaseModel
from typing import Optional
from datetime import datetime

class UserBase(BaseModel):
    username: str
    email: Optional[str] = None

class UserCreate(UserBase):
    password: str

class UserRegister(BaseModel):
    username: str
    mobile_number: str
    email: Optional[str] = None
    # Password/PIN checks happen later or separate

class UserResponse(UserBase):
    id: int
    upi_id: str
    mcc: Optional[str] = None
    balance: float
    mobile_number: Optional[str] = None

    class Config:
        from_attributes = True



class UserLookupResponse(BaseModel):
    username: str
    upi_id: str
    mcc: Optional[str] = None

class UserLookupResponse(BaseModel):
    username: str
    upi_id: str
    mcc: Optional[str] = None

class MessageCreate(BaseModel):
    receiver_upi_id: str
    content: str
    
class MessageResponse(BaseModel):
    id: int
    sender_upi_id: str
    receiver_upi_id: str
    content: str
    timestamp: datetime
    type: str = "message"
    
    class Config:
        from_attributes = True

class TransactionCreate(BaseModel):
    receiver_upi_id: str
    amount: float
    pin: str

class TransactionResponse(BaseModel):
    transaction_id: str
    sender_upi_id: str
    receiver_upi_id: str
    sender_name: Optional[str] = None
    receiver_name: Optional[str] = None
    amount: float
    status: str
    risk_score: str
    timestamp: datetime
    type: str = "transaction"

    class Config:
        from_attributes = True

class Token(BaseModel):
    access_token: str
    token_type: str

class MobileCheckRequest(BaseModel):
    mobile_number: str

class MobileCheckResponse(BaseModel):
    exists: bool
    status: str  # "new" (needs pin), "existing" (login), "not_found"
    upi_id: Optional[str] = None
    detail: Optional[str] = None
    has_device_conflict: bool = False

class PinSetRequest(BaseModel):
    mobile_number: str
    pin: str
    upi_id: Optional[str] = None

class ChangePinRequest(BaseModel):
    new_pin: str

class LoginHistoryResponse(BaseModel):
    id: int
    device_id: str
    login_time: datetime
    logout_time: Optional[datetime] = None
    ip_address: Optional[str] = None
    is_active: bool

    class Config:
        from_attributes = True
