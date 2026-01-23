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
    balance: float

    class Config:
        from_attributes = True



class UserLookupResponse(BaseModel):
    username: str
    upi_id: str

class TransactionCreate(BaseModel):
    receiver_upi_id: str
    amount: float
    pin: str

class TransactionResponse(BaseModel):
    transaction_id: str
    sender_upi_id: str
    receiver_upi_id: str
    amount: float
    status: str
    risk_score: str
    timestamp: datetime

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
