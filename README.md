# 🛡️ SafePay - Next-Gen Secure Banking

![SafePay](https://img.shields.io/badge/Security-Advanced-green) ![Platform](https://img.shields.io/badge/Platform-Flutter%20%7C%20FastAPI-blue) ![License](https://img.shields.io/badge/License-MIT-purple)

**SafePay** is a state-of-the-art mock banking application designed to demonstrate advanced security features, real-time fraud detection, and seamless cross-platform payments. It bridges the gap between secure backend infrastructure and a modern, responsive mobile experience.

## 🚀 Why SafePay?

SafePay isn't just a wallet; it's a security fortress. It implements features found in top-tier banking apps like Google Pay and PhonePe, focusing on:

*   **🔒 Device Binding**: Your account is permanently locked to your physical device ID. Hackers can't log in even if they steal your password.
*   **🧠 Intelligent Fraud Engine**: Analyzes transaction patterns in real-time (Amount, Time, Frequency) to block suspicious activity instantly.
*   **⚡ Instant Transactions**: Simulate lightning-fast UPI transfers with immediate feedback.
*   **📱 Secure Mobile Experience**: Built with Flutter, featuring root detection, secure storage, and a premium UI.

---

## 🛠️ Technology Stack

| Component | Technology | Description |
| :--- | :--- | :--- |
| **Backend** | **Python (FastAPI)** | High-performance, async API handling core logic and fraud detection. |
| **Database** | **SQLite (SQLAlchemy)** | Lightweight, relational database for robust transaction processing. |
| **Mobile App** | **Flutter (Dart)** | Cross-platform (iOS/Android) application with beautiful Material 3 design. |
| **Tunneling** | **Ngrok** | Secure tunneling to expose the local backend to the internet for remote testing. |

---

## 📋 Prerequisites

Before you start, ensure you have the following installed:

1.  **Python 3.9+**: [Download Python](https://www.python.org/downloads/)
2.  **Flutter SDK (3.10+)**: [Download Flutter](https://docs.flutter.dev/get-started/install)
3.  **Git**: [Download Git](https://git-scm.com/downloads)

*(Optional but Recommended)*: **VS Code** with Python and Flutter extensions.

---

## ⚡ Quick Start (Windows)

We have automated the boring stuff! Use our setup script to get the backend running in seconds.

### 1. Start the Backend
1.  Navigate to the project root folder.
2.  Double-click `setup_app.ps1` or run the following command in PowerShell:
    ```powershell
    .\setup_app.ps1
    ```
    *   This script will automatically check for Python, create a virtual environment, install all dependencies, and verify your configuration.
3.  Once setup is complete, double-click `start_backend.bat`.
    *   **Local Mode**: Starts the server on `0.0.0.0:8000`. Note the IP address displayed (e.g., `192.168.1.5`).
    *   **Remote Mode (Ngrok)**: Double-click `start_remote.bat`.
    *   **Remote Mode (Cloudflare)**: Double-click `start_remote_cloudflare.bat` (Requires `cloudflared` installed).


### 2. Run the Mobile App
1.  Open a terminal in the `mobile_app` folder:
    ```powershell
    cd mobile_app
    ```
2.  Install dependencies:
    ```powershell
    flutter pub get
    ```
3.  Connect your phone or start an emulator.
4.  Run the app:
    ```powershell
    flutter run
    ```

### 3. Connect App to Backend
1.  Open the **SafePay** app.
2.  Tap on **Settings** (Gear Icon).
3.  Enter your Backend URL:
    *   **Local**: `http://<YOUR_IPV4_ADDRESS>:8000` (e.g., `http://192.168.1.5:8000`)
    *   **Remote**: Paste your Ngrok URL (e.g., `https://xyz.ngrok-free.app`)
4.  Save and Login/Register!

---

## 🔧 Manual Installation (Mac/Linux/Manual)

If you prefer the command line or are on a non-Windows system:

### Backend Setup
```bash
# 1. Navigate to backend
cd backend

# 2. Create Virtual Environment
python -m venv venv
source venv/bin/activate  # On Windows: .\venv\Scripts\activate

# 3. Install Dependencies
pip install -r requirements.txt

# 4. Initialize Database
python init_db.py

# 5. Run Server
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

### Mobile App Setup
```bash
cd mobile_app
flutter pub get
flutter run
```

---

## 🧪 Testing Fraud Detection

SafePay's fraud engine is active by default. Try these scenarios to see it in action:

| Scenario | Action | Expected Result |
| :--- | :--- | :--- |
| **Normal Transfer** | Send ₹100 - ₹500 to a friend. | ✅ **Success** (Safe) |
| **High Amount** | Send ₹50,000+ (or >3x your average). | ⚠️ **Warning/Blocked** |
| **Late Night** | Transact between **12:00 AM - 5:00 AM**. | 🚩 **Risk Score Increased** |
| **Rapid Fire** | Send 5+ transactions in < 1 minute. | 🚫 **Blocked** (High Frequency) |

---

## 📚 API Documentation

Developers can explore the full backend API via Swagger UI:
*   Open [http://localhost:8000/docs](http://localhost:8000/docs) after starting the server.

---

## 🤝 Contributing

This project is for educational purposes. Feel free to fork, submit PRs, or open issues to improve the security or features!

**SafePay** — *Secure. Fast. Reliable.*