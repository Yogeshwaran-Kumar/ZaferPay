@echo off
echo ===================================================
echo   SafePay Remote Access Helper
echo ===================================================
echo.
echo This script helps you expose your local backend to the internet.
echo You need 'ngrok' installed and in your PATH.
echo.
echo [1] Starting Backend Server in a new window...
start "SafePay Backend" cmd /k "backend\venv\Scripts\activate & cd backend & uvicorn main:app --host 0.0.0.0 --port 8000 --reload"

echo.
echo [2] Starting Ngrok Tunnel...
echo.
echo IMPORTANT: 
echo 1. Look for the "Forwarding" line (e.g., https://abc.ngrok-free.app)
echo 2. Copy that URL.
echo 3. Paste it into the SafePay Mobile App settings.
echo.
ngrok http 8000
