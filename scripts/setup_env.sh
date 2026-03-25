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
if ! command -v python3 &> /dev/null
then
    echo "❌ Error: 'python3' command not found."
    exit 1
fi

# Create virtual environment if it doesn't exist
if [ ! -d ".venv" ]; then
    python3 -m venv .venv
    echo "✅ Virtual environment created in .venv"
fi

# Activate virtual environment
source .venv/bin/activate

# Install requirements
echo "📦 Installing Python dependencies..."
pip install --upgrade pip
if [ -f "scripts/requirements.txt" ]; then
    pip install -r scripts/requirements.txt
else
    echo "⚠️ scripts/requirements.txt not found. Installing playwright directly..."
    pip install playwright==1.49.1
fi

# Install Playwright browsers
echo "🌐 Installing Playwright browsers..."
playwright install --with-deps chromium

# 3. Sample Generation
echo "🎵 Generating signal samples..."
python3 generate_samples.py

echo "✅ Environment setup complete!"
echo ""
echo "To start working, activate the Python environment:"
echo "source .venv/bin/activate"
