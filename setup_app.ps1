
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "   2Way App - Automated Setup Script   " -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

# 1. Check for Python
try {
    $pythonVersion = python --version 2>&1
    Write-Host "[+] Python found: $pythonVersion" -ForegroundColor Green
} catch {
    Write-Host "[-] Python is NOT installed or not in PATH." -ForegroundColor Red
    Write-Host "    Please install Python from python.org and try again."
    exit
}

# 2. Setup Backend Virtual Environment
$backendPath = Join-Path $PSScriptRoot "backend"
$venvPath = Join-Path $backendPath "venv"

Write-Host "`n[Processing Backend...]" -ForegroundColor Yellow
if (-not (Test-Path $venvPath)) {
    Write-Host "    Creating virtual environment..."
    python -m venv $venvPath
} else {
    Write-Host "    Virtual environment already exists."
}

# 3. Install Dependencies
Write-Host "    Installing dependencies..."
$pipPath = Join-Path $venvPath "Scripts\pip.exe"
& $pipPath install -r (Join-Path $backendPath "requirements.txt")

if ($LASTEXITCODE -eq 0) {
    Write-Host "[+] Backend setup complete!" -ForegroundColor Green
} else {
    Write-Host "[-] Failed to install backend dependencies." -ForegroundColor Red
    exit
}

# 4. Database Config Warning
Write-Host "`n[Database Configuration]" -ForegroundColor Yellow
$envPath = Join-Path $backendPath ".env"
if (-not (Test-Path $envPath)) {
    Write-Host "[-] .env file missing in backend folder!" -ForegroundColor Red
    Write-Host "    You must create a .env file with DATABASE_URL="
} else {
    Write-Host "[+] .env file found. using existing configuration." -ForegroundColor Green
}

# 5. Mobile App Instructions (The "Truth" part)
Write-Host "`n[Mobile App Requirements]" -ForegroundColor Cyan
Write-Host "IMPORTANT: The mobile app CANNOT be auto-installed via this script." -ForegroundColor Yellow
Write-Host "To run the mobile app, the recipient MUST have:"
Write-Host "1. Flutter SDK Installed (flutter.dev)"
Write-Host "2. Android Studio or Xcode setup"
Write-Host "3. A connected device or emulator"
Write-Host "`nTo run the mobile app manually:"
Write-Host "   cd mobile_app"
Write-Host "   flutter pub get"
Write-Host "   flutter run"

Write-Host "`n[+] Setup script finished." -ForegroundColor Cyan
Read-Host "Press Enter to exit..."
