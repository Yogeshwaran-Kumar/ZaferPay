@echo off
echo Starting MockBank Backend Server...
echo.
echo This server will be accessible from other devices on your network.
echo Make sure your firewall allows connections on port 8000.
echo.
echo To find your computer's IP address:
echo 1. Open Command Prompt
echo 2. Run: ipconfig
echo 3. Look for "IPv4 Address" under your active network adapter
echo 4. Share that IP with others (e.g., 192.168.1.100:8000)
echo.
echo Press Ctrl+C to stop the server
echo.

cd backend
set PYTHONPATH=%CD%
uvicorn main:app --host 0.0.0.0 --port 8000 --reload