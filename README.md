# MockBank - Multi-Device UPI Payment App

A Flutter mobile app with FastAPI backend for UPI-style payments with fraud detection.

## Features

- User authentication and registration
- UPI ID based payments
- QR code payments (scan & pay)
- Manual UPI ID payments
- Transaction history
- Fraud detection and risk assessment
- Multi-device support (works across different networks)

## Setup Instructions

### Backend Setup

1. **Install Dependencies:**
   ```bash
   cd backend
   pip install fastapi uvicorn sqlalchemy pydantic python-multipart
   ```

2. **Start Backend Server:**
   - For local development: `python -m uvicorn main:app --reload`
   - For network access (multi-device): Run `start_backend.bat` or:
     ```bash
     python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
     ```

3. **Find Your IP Address:**
   - Open Command Prompt/PowerShell
   - Run: `ipconfig`
   - Look for "IPv4 Address" (e.g., 192.168.1.100)

### Mobile App Setup

1. **Install Flutter dependencies:**
   ```bash
   cd mobile_app
   flutter pub get
   ```

2. **Configure Backend URL:**
   - Open the app
   - Go to Settings (gear icon in home screen)
   - Enter your computer's IP address with port 8000
   - Example: `192.168.1.100:8000`
   - Test the connection

3. **Run the app:**
   ```bash
   flutter run
   ```

## Test Users

| Username | UPI ID | Password | Balance |
|----------|--------|----------|---------|
| userA | userA@mockbank | password123 | ₹50,000 |
| userB | userB@mockbank | password123 | ₹25,000 |
| shopC | shopC@mockbank | password123 | ₹10,000 |
| trustD | trustD@mockbank | password123 | ₹500,000 |

## Multi-Device Usage

1. Start the backend on your computer using `start_backend.bat`
2. Note your computer's IP address (from ipconfig)
3. On each device/phone:
   - Install and open the app
   - Go to Settings and enter your computer's IP:8000
   - Login with any test user credentials
   - Use the app normally - all features work across devices!

## Network Requirements

- All devices must be on the same WiFi network
- Firewall should allow port 8000
- Backend computer should not sleep/go to standby

## Troubleshooting

- **Connection failed**: Check IP address and port, ensure backend is running
- **Payment failed**: Verify UPI ID exists and you have sufficient balance
- **Can't access from other devices**: Make sure backend is running on 0.0.0.0 not 127.0.0.1

## Security Note

This is a demo application. In production, use HTTPS, proper authentication, and secure network configurations.