"""
Database Configuration - PostgreSQL (Neon Cloud)
"""

import os
import socket
import subprocess
import re
from urllib.parse import urlparse
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base
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

def resolve_db_host(hostname):
    """
    Resolve hostname to IP, falling back to Google DNS (8.8.8.8) 
    if system DNS fails.
    """
    try:
        # 1. Try standard system resolution
        return socket.gethostbyname(hostname)
    except socket.gaierror:
        print(f"[WARN] System DNS failed for {hostname}. Trying Google DNS (8.8.8.8)...")
        try:
            # 2. Fallback using PowerShell on Windows or dig on Linux
            if os.name == 'nt':
                 cmd = [
                     "powershell", "-Command", 
                     f"(Resolve-DnsName {hostname} -Server 8.8.8.8 -Type A -ErrorAction Stop).IPAddress"
                 ]
            else:
                 cmd = ["dig", "+short", "@8.8.8.8", hostname]     
            
            # Using creationflags=0x08000000 (CREATE_NO_WINDOW) to prevent hanging and windows popups
            creationflags = 0x08000000 if os.name == 'nt' else 0
            
            result = subprocess.run(
                cmd, 
                capture_output=True, 
                text=True, 
                timeout=10,
                stdin=subprocess.DEVNULL,
                creationflags=creationflags
            )
            
            # Extract valid IPv4 addresses
            ips = []
            for line in result.stdout.strip().splitlines():
                ip = line.strip()
                # Basic IPv4 validation
                if re.match(r'^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$', ip):
                    if not ip.startswith("8.8.8.8") and ip != "127.0.0.1" and not ip.startswith("192.168."):
                        ips.append(ip)
            
            if ips:
                 return ips[0] # Return first valid IP
            
            print(f"[ERROR] Failed to extract IP. Command output: {result.stdout.strip()} | stderr: {result.stderr.strip()}")
            return None
        except Exception as e:
            print(f"[ERROR] Fallback DNS resolution failed: {e}")
            return None

# Parse hostname from URL to resolve it manually
connect_args = {}
try:
    url_parts = urlparse(DATABASE_URL)
    hostname = url_parts.hostname
    
    if hostname:
         # Check if we need resolution
         resolved_ip = resolve_db_host(hostname)
         if resolved_ip:
             print(f"[INFO] Database resolved to: {resolved_ip}")
             connect_args["hostaddr"] = resolved_ip
         else:
             print(f"[ERROR] Could not resolve hostname: {hostname}")

except Exception as e:
    print(f"[WARN] Error in DNS resolution setup: {e}")

print(f"[INFO] Connecting to PostgreSQL database...")

engine = create_engine(
    DATABASE_URL,
    connect_args=connect_args,
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
