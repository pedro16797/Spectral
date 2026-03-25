# Spectral Development Environment Setup (PowerShell)

Write-Host 'Setting up Spectral Development Environment...' -ForegroundColor Cyan

# 1. Flutter Setup
Write-Host 'Installing Flutter dependencies...' -ForegroundColor Blue
if (!(Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Host 'Error: flutter command not found.' -ForegroundColor Red
    Write-Host 'Please install Flutter SDK first: https://docs.flutter.dev/get-started/install'
    exit 1
}
flutter pub get

# 2. Python Setup (Isolated Environment)
Write-Host 'Setting up isolated Python environment...' -ForegroundColor Yellow

$PYTHON_EXE = ''
if (Get-Command python3 -ErrorAction SilentlyContinue) {
    $PYTHON_EXE = 'python3'
} elseif (Get-Command python -ErrorAction SilentlyContinue) {
    $PYTHON_EXE = 'python'
} else {
    Write-Host 'Error: Python not found. Please install Python 3.' -ForegroundColor Red
    exit 1
}

# Create virtual environment if it doesn't exist
if (!(Test-Path '.venv')) {
    & $PYTHON_EXE -m venv .venv
    Write-Host 'Virtual environment created in .venv' -ForegroundColor Green
}

# Determine activation script path
$ACTIVATE_PATH = '.venv\Scripts\Activate.ps1'
$VENV_PYTHON = '.venv\Scripts\python.exe'

if (!(Test-Path $ACTIVATE_PATH)) {
    # Fallback for unix-style venv if created differently
    $ACTIVATE_PATH = '.venv\bin\Activate.ps1'
    $VENV_PYTHON = '.venv\bin\python'
}

# Install requirements
Write-Host 'Installing Python dependencies...' -ForegroundColor Blue
& $VENV_PYTHON -m pip install --upgrade pip
if (Test-Path 'scripts\requirements.txt') {
    & $VENV_PYTHON -m pip install -r scripts\requirements.txt
} else {
    Write-Host 'scripts\requirements.txt not found. Installing playwright directly...' -ForegroundColor Yellow
    & $VENV_PYTHON -m pip install playwright==1.49.1
}

# Install Playwright browsers
Write-Host 'Installing Playwright browsers...' -ForegroundColor Blue
& $VENV_PYTHON -m playwright install --with-deps chromium

# 3. Sample Generation
Write-Host 'Generating signal samples...' -ForegroundColor Blue
if (!(Test-Path 'resources\samples\audio')) { New-Item -ItemType Directory -Force -Path 'resources\samples\audio' | Out-Null }
if (!(Test-Path 'resources\samples\rf')) { New-Item -ItemType Directory -Force -Path 'resources\samples\rf' | Out-Null }
& $VENV_PYTHON generate_samples.py

Write-Host 'Environment setup complete!' -ForegroundColor Green
Write-Host ''
Write-Host 'To start working, activate the Python environment:'
Write-Host ".\$ACTIVATE_PATH" -ForegroundColor Cyan
Write-Host ''
Write-Host 'NOTE: If you get an error about script execution being disabled, you can run this script with:' -ForegroundColor Yellow
Write-Host 'powershell -ExecutionPolicy Bypass -File .\scripts\setup_env.ps1' -ForegroundColor Yellow
Write-Host 'Or permanently enable scripts (Administrator):' -ForegroundColor Yellow
Write-Host 'Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine' -ForegroundColor Yellow
