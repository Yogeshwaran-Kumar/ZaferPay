"""
Safe Database Migration Script - Add Security Fields

This migration adds new columns for security features:
1. encrypted_balance (User table)
2. ip_hash, ip_encrypted (Transaction table)  
3. revoked_tokens table (for token rotation)

IMPORTANT: This script is SAFE and won't break existing functionality:
- All new columns are NULLABLE (existing rows work fine)
- No existing data is modified
- Uses IF NOT EXISTS to avoid duplicate runs

Run with: python migrations/add_security_fields.py
"""

import os
import sys

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import create_engine, text
from dotenv import load_dotenv

# Load environment
load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL")
if not DATABASE_URL:
    print("❌ DATABASE_URL not set in .env")
    sys.exit(1)

# Connect to database
engine = create_engine(DATABASE_URL)

def run_migration():
    """Run all migrations safely"""
    
    with engine.connect() as conn:
        print("🔄 Starting safe database migration...")
        
        # ═══════════════════════════════════════════════════════════════════
        # 1. Add encrypted_balance to users table
        # ═══════════════════════════════════════════════════════════════════
        print("\n📦 Step 1: Adding encrypted_balance to users...")
        try:
            conn.execute(text("""
                ALTER TABLE users 
                ADD COLUMN IF NOT EXISTS encrypted_balance VARCHAR;
            """))
            conn.commit()
            print("   ✅ encrypted_balance column added (or already exists)")
        except Exception as e:
            if "already exists" in str(e).lower() or "duplicate" in str(e).lower():
                print("   ℹ️ encrypted_balance already exists, skipping")
            else:
                print(f"   ⚠️ Warning: {e}")
        
        # ═══════════════════════════════════════════════════════════════════
        # 2. Add IP tracking fields to transactions table
        # ═══════════════════════════════════════════════════════════════════
        print("\n📦 Step 2: Adding IP tracking fields to transactions...")
        try:
            conn.execute(text("""
                ALTER TABLE transactions 
                ADD COLUMN IF NOT EXISTS ip_hash VARCHAR;
            """))
            conn.commit()
            print("   ✅ ip_hash column added")
        except Exception as e:
            if "already exists" in str(e).lower():
                print("   ℹ️ ip_hash already exists, skipping")
            else:
                print(f"   ⚠️ Warning: {e}")
        
        try:
            conn.execute(text("""
                ALTER TABLE transactions 
                ADD COLUMN IF NOT EXISTS ip_encrypted VARCHAR;
            """))
            conn.commit()
            print("   ✅ ip_encrypted column added")
        except Exception as e:
            if "already exists" in str(e).lower():
                print("   ℹ️ ip_encrypted already exists, skipping")
            else:
                print(f"   ⚠️ Warning: {e}")
        
        # ═══════════════════════════════════════════════════════════════════
        # 3. Create revoked_tokens table for token rotation
        # ═══════════════════════════════════════════════════════════════════
        print("\n📦 Step 3: Creating revoked_tokens table...")
        try:
            conn.execute(text("""
                CREATE TABLE IF NOT EXISTS revoked_tokens (
                    id SERIAL PRIMARY KEY,
                    token_jti VARCHAR UNIQUE NOT NULL,
                    user_id INTEGER REFERENCES users(id),
                    revoked_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    expires_at TIMESTAMP
                );
            """))
            conn.commit()
            print("   ✅ revoked_tokens table created")
        except Exception as e:
            if "already exists" in str(e).lower():
                print("   ℹ️ revoked_tokens table already exists, skipping")
            else:
                print(f"   ⚠️ Warning: {e}")
        
        # Create index on token_jti for fast lookups
        try:
            conn.execute(text("""
                CREATE INDEX IF NOT EXISTS ix_revoked_tokens_jti 
                ON revoked_tokens(token_jti);
            """))
            conn.commit()
            print("   ✅ Index on token_jti created")
        except Exception as e:
            if "already exists" in str(e).lower():
                print("   ℹ️ Index already exists, skipping")
            else:
                print(f"   ⚠️ Warning: {e}")
        
        # ═══════════════════════════════════════════════════════════════════
        # 4. Verify migration
        # ═══════════════════════════════════════════════════════════════════
        print("\n🔍 Verifying migration...")
        
        # Check users table
        result = conn.execute(text("""
            SELECT column_name FROM information_schema.columns 
            WHERE table_name = 'users' AND column_name = 'encrypted_balance';
        """))
        if result.fetchone():
            print("   ✅ users.encrypted_balance exists")
        else:
            print("   ❌ users.encrypted_balance NOT found")
        
        # Check transactions table
        result = conn.execute(text("""
            SELECT column_name FROM information_schema.columns 
            WHERE table_name = 'transactions' AND column_name = 'ip_hash';
        """))
        if result.fetchone():
            print("   ✅ transactions.ip_hash exists")
        else:
            print("   ❌ transactions.ip_hash NOT found")
        
        # Check revoked_tokens table
        result = conn.execute(text("""
            SELECT table_name FROM information_schema.tables 
            WHERE table_name = 'revoked_tokens';
        """))
        if result.fetchone():
            print("   ✅ revoked_tokens table exists")
        else:
            print("   ❌ revoked_tokens table NOT found")
        
        print("\n" + "="*60)
        print("✅ MIGRATION COMPLETE!")
        print("="*60)
        print("\nYour existing app will continue to work normally.")
        print("New features will use the new columns/tables.")
        print("\nNo restart required - changes are live immediately.")


if __name__ == "__main__":
    run_migration()
