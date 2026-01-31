<p align="center">
  <img src="mobile_app/assets/icon.png" alt="SafePay Logo" width="120" height="120"/>
</p>

<h1 align="center">🛡️ SafePay</h1>

<p align="center">
  <strong>Military-Grade Secure UPI Payment Application</strong>
</p>

<p align="center">
  A production-ready payment application featuring AI-powered fraud detection, military-grade encryption, and real-time transaction security — built with FastAPI and Flutter.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Backend-FastAPI-009688?style=for-the-badge&logo=fastapi" alt="FastAPI"/>
  <img src="https://img.shields.io/badge/Mobile-Flutter-02569B?style=for-the-badge&logo=flutter" alt="Flutter"/>
  <img src="https://img.shields.io/badge/AI-XGBoost-orange?style=for-the-badge" alt="XGBoost"/>
  <img src="https://img.shields.io/badge/Encryption-AES--256-red?style=for-the-badge" alt="AES-256"/>
</p>

---

## 📋 Table of Contents

- [Overview](#-overview)
- [Key Features](#-key-features)
- [Architecture](#-architecture)
- [Security Features](#-security-features)
- [AI Fraud Detection Engine](#-ai-fraud-detection-engine)
- [Technology Stack](#-technology-stack)
- [Project Structure](#-project-structure)
- [Getting Started](#-getting-started)
- [API Documentation](#-api-documentation)
- [Mobile App Features](#-mobile-app-features)
- [Database Schema](#-database-schema)
- [Configuration](#-configuration)
- [Deployment](#-deployment)

---

## 🎯 Overview

**SafePay** is a comprehensive UPI-style payment application designed with security as the foundational principle. It implements a **3-stage fraud detection pipeline** inspired by industry leaders like Google Pay, featuring:

- **Stage 1: REFLEXES** — 50+ hard-coded rules for instant threat detection
- **Stage 2: NETWORK** — Social graph trust validation
- **Stage 3: BRAIN** — 28-feature AI anomaly detection using XGBoost/IsolationForest

The system processes transactions through multiple security layers before approval, ensuring protection against fraud, replay attacks, and unauthorized access.

---

## ✨ Key Features

### 🔐 Security
| Feature | Description |
|---------|-------------|
| **AES-256 Encryption** | All sensitive data (balances, messages, phone numbers) encrypted at rest |
| **Argon2id Password Hashing** | Industry's strongest password hashing algorithm with 64MB memory cost |
| **HMAC Request Signing** | Every transaction request is cryptographically signed to prevent tampering |
| **Token Rotation** | Refresh tokens are single-use and revoked after each exchange |
| **Device Binding** | Single-device login enforcement with device hash verification |
| **Rate Limiting** | Brute-force protection (5 attempts/minute on login) |
| **Jailbreak Detection** | Mobile app detects rooted/jailbroken devices and blocks transactions |

### 💳 Payments
| Feature | Description |
|---------|-------------|
| **QR Code Scanning** | Scan any UPI QR code to initiate payments |
| **Contact Integration** | Pay contacts directly from phone contacts |
| **Transaction History** | Full history with detailed transaction breakdowns |
| **Chat Integration** | WhatsApp-style chat with integrated payments |
| **Daily Limits** | Enforced limits per receiver (₹1L P2P, ₹3L Merchant) |
| **Idempotency Protection** | Duplicate transaction prevention |

### 🤖 AI-Powered
| Feature | Description |
|---------|-------------|
| **3-Stage Fraud Pipeline** | Rules → Social Graph → AI Analysis |
| **28 Feature Extraction** | Comprehensive behavioral and transactional features |
| **Auto-Retraining** | AI model retrains every 24 hours automatically |
| **Champion-Challenger** | A/B testing for model updates |
| **Geo-Velocity Detection** | Impossible travel detection using IP geolocation |
| **Adaptive Learning** | Personal trust limits that grow with usage |

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        MOBILE APP (Flutter)                      │
│  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────────────┐│
│  │ Jailbreak │ │   HMAC    │ │  Secure   │ │    Processing     ││
│  │ Detection │ │  Signing  │ │  Storage  │ │   Shield Screen   ││
│  └───────────┘ └───────────┘ └───────────┘ └───────────────────┘│
└─────────────────────────────────────────────────────────────────┘
                                │
                                │ HTTPS + HMAC Signed Requests
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                     BACKEND (FastAPI)                            │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                   SECURITY LAYER                          │  │
│  │  • Rate Limiting (slowapi)                                │  │
│  │  • HMAC Verification                                      │  │
│  │  • JWT Token Validation                                   │  │
│  │  • Device Binding Check                                   │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              │                                   │
│                              ▼                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              3-STAGE FRAUD DETECTION ENGINE               │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │  │
│  │  │ STAGE 1     │  │ STAGE 2     │  │ STAGE 3     │       │  │
│  │  │ REFLEXES    │─▶│ NETWORK     │─▶│ BRAIN       │       │  │
│  │  │ (50+ Rules) │  │ (Trust Graph)│  │ (AI/ML)     │       │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘       │  │
│  └───────────────────────────────────────────────────────────┘  │
│                              │                                   │
│                              ▼                                   │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │                    DATA LAYER                             │  │
│  │  • SQLite/PostgreSQL with SQLAlchemy                      │  │
│  │  • AES-256 Encrypted Fields                               │  │
│  │  • SHA-256 Searchable Hashes                              │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔒 Security Features

### Encryption Stack

```
┌────────────────────────────────────────────────────────┐
│                    ENCRYPTION SCHEME                    │
├────────────────────────────────────────────────────────┤
│ Field Type          │ Storage Method                   │
├────────────────────────────────────────────────────────┤
│ PIN/Password        │ Argon2id Hash (64MB, 2 iterations)│
│ Balance             │ Plain + AES-256 Encrypted         │
│ Mobile Number       │ HMAC-SHA256 Hash + AES-256        │
│ Email               │ HMAC-SHA256 Hash + AES-256        │
│ Device ID           │ HMAC-SHA256 Hash + AES-256        │
│ IP Address          │ HMAC-SHA256 Hash + AES-256        │
│ Transaction Amount  │ Plain + AES-256 Encrypted         │
│ UPI ID              │ Plain (designed to be shared)     │
└────────────────────────────────────────────────────────┘
```

### Request Signing (HMAC)

Every sensitive request includes:
```
X-Signature: HMAC-SHA256(timestamp + body, HMAC_SECRET)
X-Timestamp: Unix timestamp (must be within 5 minutes)
```

This prevents:
- **Tampering** — Any modification invalidates the signature
- **Replay Attacks** — Timestamp ensures requests are fresh
- **Man-in-the-Middle** — Attacker cannot generate valid signatures

### Token Security

| Token Type | Lifetime | Features |
|------------|----------|----------|
| Access Token | 15 minutes | Contains device_id binding |
| Refresh Token | 7 days | Single-use with JTI tracking |

When a refresh token is used, it's immediately revoked. Reuse attempts are flagged as potential theft.

---

## 🧠 AI Fraud Detection Engine

### 3-Stage Pipeline

#### Stage 1: REFLEXES (Hard Rules)
```
┌─────────────────────────────────────────────────────────────┐
│ REFLEX RULES (Instant Block/Flag)                           │
├─────────────────────────────────────────────────────────────┤
│ F1  │ Velocity Limit (5 tx/hour default)                    │
│ F2  │ Amount Spike (3x average)                             │
│ F3  │ Stranger High Amount (₹5,000 limit for new receivers) │
│ F4  │ Night Time Check (22:00-05:00)                        │
│ F5  │ Weekend High Amount                                   │
│ F6  │ Balance Drain (>50% in one transaction)               │
│ F7  │ Receiver Concentration (>50% to single receiver)      │
│ F18 │ Daily Receiver Limit (₹1L P2P, ₹3L Merchant)          │
│ F29 │ Geo-Velocity (Impossible Travel Detection)            │
│ ... │ 50+ more rules                                        │
└─────────────────────────────────────────────────────────────┘
```

#### Stage 2: NETWORK (Social Graph)
- **Trust Depth**: Direct friend (depth 1) vs Friend-of-friend (depth 2) vs Stranger (depth 0)
- **Trust Score**: Builds over time with successful transactions
- **Adaptive Limits**: Users can gradually increase their personal trust limits

#### Stage 3: BRAIN (AI Analysis)
28 features extracted per transaction:

| Category | Features |
|----------|----------|
| **Transaction** | amount, hour, day_of_week, is_weekend, is_night |
| **Velocity** | tx_count_1h, tx_count_24h, total_amount_24h |
| **Behavioral** | avg_amount, amount_vs_avg_ratio, minutes_since_last_tx |
| **Network** | unique_receivers_24h, is_new_receiver, trust_score |
| **Account** | account_age_days, receiver_unique_senders_24h |
| **Session** | session_tx_count, avg_session_tx, consecutive_tx_count |
| **Recipient** | recipient_age_days, recipient_tx_volume |
| **Pattern** | hour_frequency, day_frequency, amount_percentile |
| **Financial** | balance_utilization, is_first_time_amount |

### MCC Tier System

The engine applies different rules based on merchant category:

| Tier | Examples | Special Handling |
|------|----------|------------------|
| **ESSENTIAL** | Hospitals, Schools, Utilities | Never blocked, bypasses all checks |
| **HIGH_VALUE** | Jewelry, Legal Services | Big amounts OK, strict velocity (2/hour) |
| **RETAIL** | Grocery, Restaurants, Transport | High velocity OK (20/hour), ₹1L limit |
| **SERVICES** | Hotels, Electronics, Travel | Standard checks, ₹2L limit |
| **PERSONAL** | P2P Transfers | Full social graph checks, ₹1L/receiver/day |

### Auto-Learning System

```
┌─────────────────────────────────────────────────────────────┐
│                  AI TRAINING PIPELINE                        │
├─────────────────────────────────────────────────────────────┤
│ 1. Scheduled every 24 hours (APScheduler)                   │
│ 2. Fetches last 10,000 transactions                         │
│ 3. Incorporates fraud feedback (blocked + user reports)     │
│ 4. Trains challenger model (IsolationForest)                │
│ 5. Champion-Challenger comparison                            │
│ 6. If challenger is 5% better → promote to champion         │
│ 7. Model signed with HMAC to prevent tampering              │
└─────────────────────────────────────────────────────────────┘
```

---

## 💻 Technology Stack

### Backend
| Component | Technology |
|-----------|------------|
| Framework | FastAPI (Python 3.10+) |
| Database | SQLite (dev) / PostgreSQL (prod) |
| ORM | SQLAlchemy |
| Authentication | JWT (python-jose) |
| Password Hashing | Argon2id |
| Encryption | Fernet (cryptography) |
| Rate Limiting | slowapi |
| ML Framework | scikit-learn, XGBoost |
| Scheduler | APScheduler |
| Geolocation | geoip2 (MaxMind GeoLite2) |

### Mobile App
| Component | Technology |
|-----------|------------|
| Framework | Flutter (Dart) |
| HTTP Client | http package |
| Secure Storage | flutter_secure_storage |
| QR Scanning | mobile_scanner, google_mlkit_barcode_scanning |
| Contacts | flutter_contacts |
| Security | flutter_jailbreak_detection |
| Crypto | crypto (HMAC-SHA256) |
| Animations | Lottie |

---

## 📁 Project Structure

```
SafePay/
├── backend/
│   ├── main.py                 # FastAPI application (1900+ lines)
│   ├── models.py               # SQLAlchemy models (13 tables)
│   ├── schemas.py              # Pydantic schemas
│   ├── auth.py                 # Authentication (Argon2id, JWT, HMAC)
│   ├── security.py             # AES-256 encryption module
│   ├── fraud_engine.py         # 3-stage fraud detection (1400+ lines)
│   ├── ai_scheduler.py         # Auto-retraining scheduler
│   ├── database.py             # Database connection
│   ├── logging_config.py       # Structured logging
│   ├── requirements.txt        # Python dependencies
│   └── GeoLite2-City.mmdb      # IP geolocation database
│
├── mobile_app/
│   ├── lib/
│   │   ├── main.dart                    # App entry point
│   │   ├── api_service.dart             # API client
│   │   ├── home_screen.dart             # Dashboard
│   │   ├── pay_screen.dart              # Payment flow
│   │   ├── processing_shield_screen.dart # Security visualization
│   │   ├── risk_analysis_screen.dart    # AI analysis display
│   │   ├── login_screen.dart            # Authentication
│   │   ├── scan_screen.dart             # QR scanner
│   │   ├── conversation_screen.dart     # Chat + payments
│   │   └── services/
│   │       ├── api_client.dart          # HMAC signing
│   │       ├── auth_service.dart        # Token management
│   │       ├── transaction_service.dart # Transaction logic
│   │       └── user_service.dart        # User operations
│   ├── pubspec.yaml             # Flutter dependencies
│   └── assets/                  # Icons, animations
│
├── *.html                       # Documentation files
├── setup_app.ps1                # Windows setup script
├── start_backend.bat            # Backend startup script
└── README.md                    # This file
```

---

## 🚀 Getting Started

### Prerequisites
- Python 3.10+
- Flutter 3.10+
- Node.js (optional, for Cloudflare tunnel)

### Backend Setup

```bash
# Navigate to backend
cd backend

# Create virtual environment
python -m venv .venv
.venv\Scripts\activate  # Windows
# source .venv/bin/activate  # Linux/Mac

# Install dependencies
pip install -r requirements.txt

# Create .env file
echo "SECRET_KEY=your-super-secret-jwt-key" > .env
echo "HMAC_SECRET=your-hmac-signing-secret" >> .env
echo "MASTER_KEY=$(python -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())')" >> .env
echo "HASH_SALT=your-random-salt-for-hashing" >> .env

# Run the server
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

### Mobile App Setup

```bash
# Navigate to mobile app
cd mobile_app

# Get dependencies
flutter pub get

# Update API URL in lib/services/api_client.dart
# Set your backend URL

# Run the app
flutter run
```

### Quick Start (Windows)

```powershell
# Run the setup script
.\setup_app.ps1
```

---

## 📚 API Documentation

Once the backend is running, access:
- **Swagger UI**: http://localhost:8000/docs
- **ReDoc**: http://localhost:8000/redoc

### Key Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/token` | POST | Login (returns JWT) |
| `/auth/refresh` | POST | Token rotation |
| `/auth/check-mobile` | POST | Check if user exists |
| `/auth/set-pin` | POST | Register/update PIN |
| `/users/me` | GET | Get current user |
| `/transactions/` | POST | Create transaction |
| `/transactions/history` | GET | Get transaction history |
| `/conversations/{upi}` | GET | Get chat + transactions |
| `/admin/ai/stats` | GET | AI model statistics |
| `/admin/ai/retrain` | POST | Manual AI retraining |

---

## 📱 Mobile App Features

### Security Flow Visualization

The **Processing Shield Screen** shows real-time security checks during payment:

1. **Integrity Scan** — Jailbreak/root detection, tamper detection
2. **Encrypting** — HMAC signature generation
3. **Analyzing** — AI fraud analysis
4. **Processing** — Transaction execution
5. **Result** — Success/Failure with security label

### Key Screens

| Screen | Features |
|--------|----------|
| **Home** | Balance, recent transactions, quick actions |
| **Pay** | QR scan, manual UPI entry, contact selection |
| **Conversation** | Chat with payments (WhatsApp-style) |
| **Transaction History** | Full history with filters |
| **Risk Analysis** | Shows AI decision breakdown |
| **Settings** | Theme, security, about |

---

## 🗄️ Database Schema

### Core Tables (13 Total)

| Table | Purpose |
|-------|---------|
| `users` | User accounts with encrypted PII |
| `transactions` | Payment records with encryption |
| `sender_profiles` | Sender behavior for fraud detection |
| `receiver_profiles` | Receiver behavior patterns |
| `messages` | Encrypted chat messages |
| `login_history` | Session tracking |
| `device_profiles` | Device usage statistics |
| `fraud_events` | AI training data (blocked transactions) |
| `user_trust_graph` | Social trust network |
| `user_fraud_reports` | User-reported fraud cases |
| `idempotency_keys` | Duplicate prevention |
| `revoked_tokens` | Token rotation security |

---

## ⚙️ Configuration

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `SECRET_KEY` | ✅ | JWT signing key |
| `HMAC_SECRET` | ✅ | Request signing key |
| `MASTER_KEY` | ✅ | AES-256 encryption key (Fernet format) |
| `HASH_SALT` | ⚠️ | Salt for hash functions |
| `DATABASE_URL` | ❌ | PostgreSQL URL (defaults to SQLite) |

### Permanent Limits (Hardcoded)

| Limit | Value | Description |
|-------|-------|-------------|
| P2P Daily | ₹1,00,000 | Per receiver per day |
| Merchant Daily | ₹3,00,000 | Per merchant per day |
| Login Rate | 5/minute | Per IP address |
| Token Lifetime | 15 min | Access token |
| Refresh Lifetime | 7 days | Refresh token |

---

## 🌐 Deployment

### Render (Free Tier)

1. Push code to GitHub
2. Connect to Render
3. Set environment variables
4. Deploy with:
   - **Build Command**: `pip install -r requirements.txt`
   - **Start Command**: `uvicorn main:app --host 0.0.0.0 --port $PORT`

### Local Tunnel (Development)

```bash
# Install cloudflared
# Run tunnel
cloudflared tunnel --url http://localhost:8000
```

---

## 📊 Security Audit Results

| Category | Status | Details |
|----------|--------|---------|
| Encryption at Rest | ✅ | AES-256 for all sensitive fields |
| Encryption in Transit | ✅ | HTTPS + HMAC signing |
| Password Security | ✅ | Argon2id with 64MB memory |
| Session Security | ✅ | Token rotation, device binding |
| Fraud Detection | ✅ | 3-stage pipeline, 28 features |
| Rate Limiting | ✅ | slowapi integration |
| Input Validation | ✅ | Pydantic schemas |
| Device Security | ✅ | Jailbreak detection, SIM binding |

---

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

---

## 📄 License

This project is proprietary software developed for a hackathon demonstration.

---

## 👏 Acknowledgments

- **FastAPI** — High-performance Python web framework
- **Flutter** — Beautiful cross-platform UI toolkit
- **scikit-learn** — Machine learning library
- **MaxMind GeoLite2** — IP geolocation database

---

<p align="center">
  <strong>Built with 🛡️ Security First Philosophy</strong>
</p>

<p align="center">
  <sub>SafePay — Where Every Transaction is Protected</sub>
</p>