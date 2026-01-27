"""
Database Configuration - PostgreSQL (Neon Cloud)
"""

import os
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# ═══════════════════════════════════════════════════════════════════════════
# POSTGRESQL DATABASE CONNECTION
# ═══════════════════════════════════════════════════════════════════════════

DATABASE_URL = os.getenv("DATABASE_URL")

if not DATABASE_URL:
    raise ValueError("DATABASE_URL environment variable is required. Check your .env file.")

# Handle URL format variations (postgres:// -> postgresql://)
if DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = DATABASE_URL.replace("postgres://", "postgresql://", 1)

print(f"🐘 Connected to PostgreSQL database")

engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,    # Verify connections before use
    pool_size=20,          # Increased connection pool size
    max_overflow=40,       # Increased overflow limit
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
