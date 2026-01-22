@echo off
echo ===================================================
echo   MockBank Remote Access Launcher
echo ===================================================
echo.
echo 1. Ensure you have ngrok installed.
echo    If not, download from: https://ngrok.com/download
echo.
echo 2. Open a NEW terminal and run:
echo    ngrok http 8000
echo.
echo 3. Copy the 'Forwarding' URL (e.g., https://xyz.ngrok-free.app)
echo    and enter it in the Mobile App Settings.
echo.
echo ===================================================
echo Starting Backend Server on Port 8000...
echo.
cd backend
python -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
pause
