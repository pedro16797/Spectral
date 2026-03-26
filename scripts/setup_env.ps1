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

# 3. Android SDK Setup
Write-Host '🤖 Checking Android SDK...' -ForegroundColor Cyan
$ANDROID_CONFIG = flutter config | Out-String
$HAS_SDK = $ANDROID_CONFIG -match "android-sdk: (.+)"
$SDK_PATH = if ($HAS_SDK) { $Matches[1].Trim() } else { "" }

if ([string]::IsNullOrWhiteSpace($SDK_PATH) -or !(Test-Path $SDK_PATH)) {
    Write-Host '⚠️ Android SDK not configured in Flutter.' -ForegroundColor Yellow
    $LOCAL_SDK_DIR = "$PSScriptRoot\..\sdks\android"
    if (!(Test-Path $LOCAL_SDK_DIR)) { $LOCAL_SDK_DIR = "$pwd\sdks\android" }

    if (Test-Path $LOCAL_SDK_DIR) {
        Write-Host "✅ Local Android SDK found at $LOCAL_SDK_DIR. Configuring Flutter..." -ForegroundColor Green
        flutter config --android-sdk "$LOCAL_SDK_DIR"
    } else {
        $response = Read-Host "Would you like to automatically download a minimal Android SDK into '$LOCAL_SDK_DIR'? (y/n)"
        if ($response -eq 'y' -or $response -eq 'yes') {
            New-Item -ItemType Directory -Force -Path "$LOCAL_SDK_DIR\cmdline-tools" | Out-Null

            Write-Host '📥 Downloading Android Command Line Tools...' -ForegroundColor Blue
            $CMDLINE_VERSION = "11076708"
            $URL = "https://dl.google.com/android/repository/commandlinetools-win-${CMDLINE_VERSION}_latest.zip"
            $DEST = "$LOCAL_SDK_DIR\cmdline-tools.zip"

            Invoke-WebRequest -Uri $URL -OutFile $DEST
            Expand-Archive -Path $DEST -DestinationPath "$LOCAL_SDK_DIR\cmdline-tools" -Force
            Move-Item -Path "$LOCAL_SDK_DIR\cmdline-tools\cmdline-tools" -Destination "$LOCAL_SDK_DIR\cmdline-tools\latest" -Force
            Remove-Item -Path $DEST -Force

            Write-Host '⚙️ Installing essential SDK packages (Platforms, Build Tools)...' -ForegroundColor Blue
            $SDK_MANAGER = "$LOCAL_SDK_DIR\cmdline-tools\latest\bin\sdkmanager.bat"
            # Accept licenses and install
            $processInfo = New-Object System.Diagnostics.ProcessStartInfo
            $processInfo.FileName = $SDK_MANAGER
            $processInfo.Arguments = "--sdk_root=`"$LOCAL_SDK_DIR`" `"platform-tools`" `"platforms;android-34`" `"build-tools;34.0.0`""
            $processInfo.RedirectStandardInput = $true
            $processInfo.UseShellExecute = $false
            $process = [System.Diagnostics.Process]::Start($processInfo)
            for ($i=0; $i -lt 10; $i++) { $process.StandardInput.WriteLine("y") } # Accept licenses
            $process.WaitForExit()

            Write-Host '✅ Android SDK installed. Configuring Flutter...' -ForegroundColor Green
            $env:ANDROID_HOME = $LOCAL_SDK_DIR
            $env:ANDROID_SDK_ROOT = $LOCAL_SDK_DIR
            flutter config --android-sdk "$LOCAL_SDK_DIR"

            # Accept licenses via flutter doctor
            $FLUTTER_PATH = (Get-Command flutter).Source
            $licenseProcess = New-Object System.Diagnostics.ProcessStartInfo
            $licenseProcess.FileName = "cmd.exe"
            $licenseProcess.Arguments = "/c `"$FLUTTER_PATH`" doctor --android-licenses"
            $licenseProcess.RedirectStandardInput = $true
            $licenseProcess.UseShellExecute = $false
            $p = [System.Diagnostics.Process]::Start($licenseProcess)
            if ($p) {
                # Give it a moment to start
                Start-Sleep -Seconds 2
                for ($i=0; $i -lt 10; $i++) {
                    try { $p.StandardInput.WriteLine("y") } catch {}
                }
                $p.WaitForExit()
            }
        } else {
            Write-Host 'ℹ️ Skipping automated Android SDK setup.' -ForegroundColor Gray
        }
    }
} else {
    Write-Host "✅ Android SDK detected at $SDK_PATH" -ForegroundColor Green
}

# 4. Sample Generation
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
