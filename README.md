# 2way - Mock Banking Application

A secure, cross-platform mock banking system designed to demonstrate payment fraud detection, device binding, and real-time transactions. This project consists of a **FastAPI Backend** and a **Flutter Mobile App**.

## 🚀 Features

-   **Secure Authentication**:
    -   **Device Binding**: Locks a user account to a specific device ID. Login attempts from unauthorized devices are blocked.
    -   **JWT Authentication**: Secure session management.
-   **Fraud Detection Engine**:
    -   Analyzes transactions in real-time.
    -   **Risk Factors**: High transaction amounts, late-night activity (12 AM - 5 AM), and high-frequency transfers.
    -   **Actions**: Flags transactions as `SAFE`, `WARN`, or `HIGH` risk. High-risk transactions are automatically blocked.
-   **Real-time Transactions**:
    -   Send and receive money simulates instant UPI transfers.
    -   View transaction history with risk scores.
-   **Cross-Platform Mobile App**:
    -   Built with Flutter for iOS and Android.
    -   QR Code scanning for easy payments (simulated).

---

## 🛠️ Technology Stack

-   **Backend**: Python, FastAPI, SQLAlchemy, SQLite
-   **Mobile App**: Flutter (Dart)
-   **Tools**: Ngrok (for remote access/tunneling)

---

## 📋 Prerequisites

Before running the project, ensure you have the following installed:

1.  **Python 3.9+**: [Download Python](https://www.python.org/downloads/)
2.  **Flutter SDK**: [Download Flutter](https://docs.flutter.dev/get-started/install)
3.  **Git**: [Download Git](https://git-scm.com/downloads)

---

## ⚡ How to Run

You can run the application in two ways: **Locally** (same WiFi network) or **Remotely** (over the internet using Ngrok).

### Option 1: Quick Start (Windows) - **RECOMMENDED**

We have provided batch scripts to make running the backend easy.

#### 1. Run the Backend
*   **For Local Use (Same WiFi):**
    Double-click `start_backend.bat`.
    *   This starts the server on `0.0.0.0:8000`.
    *   It will display your local IP address (e.g., `192.168.1.5`). **Note this IP.**

*   **For Remote Use (Different Networks):**
    Double-click `start_remote.bat`.
    *   This starts the server and provides an **Ngrok URL** (e.g., `https://xyz.ngrok-free.app`).
    *   **Copy this URL.**

#### 2. Configure & Run the Mobile App
1.  Open the `mobile_app` folder in your terminal or VS Code.
2.  Connect your physical Android/iOS device or start an emulator.
3.  Run the app:
    ```bash
    cd mobile_app
    flutter run
    ```
4.  **In the App**:
    *   Go to **Settings**.
    *   Enter the **Base URL**:
        *   If using Local: `http://<YOUR_IP_ADDRESS>:8000` (e.g., `http://192.168.1.5:8000`)
        *   If using Remote: Paste the **Ngrok URL** (e.g., `https://xyz.ngrok-free.app`)
    *   Save and Login.

---

### Option 2: Manual Setup (Terminal)

If you prefer using the terminal directly:

#### Backend Setup
1.  Navigate to the backend directory:
    ```bash
    cd backend
    ```
2.  (Optional) Create and activate a virtual environment:
    ```bash
    python -m venv venv
    .\venv\Scripts\activate
    ```
3.  Install dependencies:
    ```bash
    pip install fastapi uvicorn sqlalchemy python-jose[cryptography] passlib[bcrypt] python-multipart
    ```
4.  Start the server:
    ```bash
    uvicorn main:app --host 0.0.0.0 --port 8000 --reload
    ```
    *   **Note**: To use Ngrok manually, run `ngrok http 8000` in a separate terminal.

#### Mobile App Setup
1.  Navigate to the mobile app directory:
    ```bash
    cd mobile_app
    ```
2.  Get dependencies:
    ```bash
    flutter pub get
    ```
3.  Run the app:
    ```bash
    flutter run
    ```

---

## 📚 API Documentation

Once the backend is running, you can explore the full API documentation (Swagger UI):

-   **Local URL**: [http://localhost:8000/docs](http://localhost:8000/docs)
-   **Key Endpoints**:
    -   `POST /token`: Login and receive access bearer token.
    -   `POST /transactions/`: Create a new transaction (triggers fraud engine).
    -   `GET /transactions/history`: Fetch user transaction history.
    -   `GET /users/me`: Get current user profile details.

---

## 🧪 Testing Fraud Detection
To test the fraud engine, try these scenarios in the app:
1.  **High Amount**: Send a transaction significantly larger than your history (e.g., > 3x average). -> *May trigger WARN/HIGH*.
2.  **Late Night**: Send money between 12 AM and 5 AM. -> *Increases Risk Score*.
3.  **Rapid Fire**: Send multiple transactions within 1 minute. -> *Increases Risk Score*.