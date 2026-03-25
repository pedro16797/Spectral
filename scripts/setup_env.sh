#!/bin/bash

# Exit on error
set -e

echo "🔧 Setting up Spectral Development Environment..."

# 1. Flutter Setup
echo "💙 Installing Flutter dependencies..."
if ! command -v flutter &> /dev/null
then
    echo "❌ Error: 'flutter' command not found."
    echo "Please install Flutter SDK first: https://docs.flutter.dev/get-started/install"
    exit 1
fi
flutter pub get

# 2. Python Setup (Isolated Environment)
echo "🐍 Setting up isolated Python environment..."

# Find Python executable
if command -v python3 &> /dev/null; then
    PYTHON_EXE="python3"
elif command -v python &> /dev/null; then
    PYTHON_EXE="python"
else
    echo "❌ Error: Python not found. Please install Python 3."
    exit 1
fi

# Create virtual environment if it doesn't exist
if [ ! -d ".venv" ]; then
    $PYTHON_EXE -m venv .venv
    echo "✅ Virtual environment created in .venv"
fi

# Determine activation script path
if [ -f ".venv/Scripts/activate" ]; then
    ACTIVATE_PATH=".venv/Scripts/activate"
    VENV_PYTHON=".venv/Scripts/python"
else
    ACTIVATE_PATH=".venv/bin/activate"
    VENV_PYTHON=".venv/bin/python"
fi

# Activate virtual environment
source "$ACTIVATE_PATH"

# Install requirements
echo "📦 Installing Python dependencies..."
$VENV_PYTHON -m pip install --upgrade pip
if [ -f "scripts/requirements.txt" ]; then
    $VENV_PYTHON -m pip install -r scripts/requirements.txt
else
    echo "⚠️ scripts/requirements.txt not found. Installing playwright directly..."
    $VENV_PYTHON -m pip install playwright==1.49.1
fi

# Install Playwright browsers
echo "🌐 Installing Playwright browsers..."
# Use playwright command if available in path, or call via python module
if command -v playwright &> /dev/null; then
    playwright install --with-deps chromium
else
    $VENV_PYTHON -m playwright install --with-deps chromium
fi

# 3. Sample Generation
echo "🎵 Generating signal samples..."
mkdir -p resources/samples/audio resources/samples/rf
$VENV_PYTHON generate_samples.py

echo "✅ Environment setup complete!"
echo ""
echo "To start working, activate the Python environment:"
if [[ "$ACTIVATE_PATH" == *Scripts/activate ]]; then
    echo "For Bash/Git Bash: source $ACTIVATE_PATH"
    echo "For PowerShell: .\\${ACTIVATE_PATH//\//\\}.ps1"
    echo ""
    echo "NOTE: If PowerShell fails due to execution policy, run with bypass:"
    echo "powershell -ExecutionPolicy Bypass -File .\\scripts\\setup_env.ps1"
    echo "Or permanently enable scripts (Administrator):"
    echo "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine"
else
    echo "source $ACTIVATE_PATH"
fi
