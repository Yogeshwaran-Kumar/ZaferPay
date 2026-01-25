from sqlalchemy import Column, Integer, String, Float, DateTime, ForeignKey, Boolean, Index
from sqlalchemy.orm import relationship
from database import Base
import datetime

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String, unique=True, index=True)
    mobile_number = Column(String, unique=True, index=True, nullable=True)
    email = Column(String, unique=True, index=True)
    hashed_password = Column(String)
    upi_id = Column(String, unique=True, index=True)  # e.g., user@mockbank
    mcc = Column(String, nullable=True)  # Merchant Category Code (e.g., 5411)
    device_id = Column(String, nullable=True)
    last_active_at = Column(DateTime, nullable=True)  # Track when this device was last active
    balance = Column(Float, default=0.0)

    # Profiles for Rule-Based Fraud Detection
    sender_profile = relationship("SenderProfile", back_populates="user", uselist=False)
    receiver_profile = relationship("ReceiverProfile", back_populates="user", uselist=False)

class Transaction(Base):
    __tablename__ = "transactions"

    id = Column(Integer, primary_key=True, index=True)
    transaction_id = Column(String, unique=True, index=True)
    sender_id = Column(Integer, ForeignKey("users.id"))
    receiver_id = Column(Integer, ForeignKey("users.id"))
    amount = Column(Float)
    timestamp = Column(DateTime, default=datetime.datetime.utcnow)
    status = Column(String)  # SUCCESS, BLOCKED, FAILED
    risk_score = Column(String)  # SAFE, WARN, HIGH
    
    # Indexes for faster queries on transaction history
    __table_args__ = (
        Index('ix_transactions_sender_id', 'sender_id'),
        Index('ix_transactions_receiver_id', 'receiver_id'),
    )
    
    sender = relationship("User", foreign_keys=[sender_id])
    receiver = relationship("User", foreign_keys=[receiver_id])

class SenderProfile(Base):
    __tablename__ = "sender_profiles"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), unique=True)
    
    avg_transaction_amount = Column(Float, default=0.0)
    total_transactions_count = Column(Integer, default=0)
    monthly_volume = Column(Float, default=0.0)
    last_transaction_time = Column(DateTime, nullable=True)
    
    user = relationship("User", back_populates="sender_profile")

class ReceiverProfile(Base):
    __tablename__ = "receiver_profiles"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), unique=True)
    
    total_received_amount = Column(Float, default=0.0)
    total_received_count = Column(Integer, default=0)
    unique_senders_count = Column(Integer, default=0)
    
    user = relationship("User", back_populates="receiver_profile")

class Message(Base):
    __tablename__ = "messages"

    id = Column(Integer, primary_key=True, index=True)
    sender_id = Column(Integer, ForeignKey("users.id"))
    receiver_id = Column(Integer, ForeignKey("users.id"))
    content = Column(String)
    timestamp = Column(DateTime, default=datetime.datetime.utcnow)
    
    sender = relationship("User", foreign_keys=[sender_id])
    receiver = relationship("User", foreign_keys=[receiver_id])

class LoginHistory(Base):
    __tablename__ = "login_history"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    # Updated Schema
    device_id = Column(String)
    login_time = Column(DateTime, default=datetime.datetime.utcnow)
    logout_time = Column(DateTime, nullable=True)
    is_active = Column(Boolean, default=True)
    ip_address = Column(String, nullable=True)
    
    user = relationship("User", back_populates="login_history")

# Add back_populates to User model as well
User.login_history = relationship("LoginHistory", back_populates="user")
