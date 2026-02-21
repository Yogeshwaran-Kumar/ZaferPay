@echo off
echo Finding your IP address for MockBank backend...
echo.
ipconfig | findstr /R /C:"IPv4 Address"
echo.
echo Use one of the above IPv4 addresses with port 8000
echo Example: 192.168.1.100:8000
echo.
echo Make sure to run start_backend.bat to start the server.
pause