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

# 3. Android SDK Setup
echo "🤖 Checking Android SDK..."
ANDROID_SDK_PATH=$(flutter config | grep "android-sdk" | cut -d ":" -f 2 | xargs)

if [ -z "$ANDROID_SDK_PATH" ] || [ ! -d "$ANDROID_SDK_PATH" ]; then
    echo "⚠️ Android SDK not configured in Flutter."
    LOCAL_SDK_DIR="$(pwd)/sdks/android"

    if [ -d "$LOCAL_SDK_DIR" ]; then
        echo "✅ Local Android SDK found at $LOCAL_SDK_DIR. Configuring Flutter..."
        flutter config --android-sdk "$LOCAL_SDK_DIR"
    else
        echo "Would you like to automatically download a minimal Android SDK into '$LOCAL_SDK_DIR'? (y/n)"
        read -r response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
            mkdir -p "$LOCAL_SDK_DIR/cmdline-tools"

            # Detect OS for command line tools download
            OS_TYPE="linux"
            if [[ "$OSTYPE" == "darwin"* ]]; then
                OS_TYPE="mac"
            fi

            echo "📥 Downloading Android Command Line Tools..."
            # Note: Hardcoded version for stability, can be updated as needed
            CMDLINE_VERSION="11076708"
            URL="https://dl.google.com/android/repository/commandlinetools-${OS_TYPE}-${CMDLINE_VERSION}_latest.zip"

            curl -L "$URL" -o "cmdline-tools.zip"
            unzip -q "cmdline-tools.zip" -d "$LOCAL_SDK_DIR/cmdline-tools"
            mv "$LOCAL_SDK_DIR/cmdline-tools/cmdline-tools" "$LOCAL_SDK_DIR/cmdline-tools/latest"
            rm "cmdline-tools.zip"

            echo "⚙️ Installing essential SDK packages (Platforms, Build Tools)..."
            export JAVA_HOME=$JAVA_HOME # Ensure JAVA_HOME is passed if set
            yes | "$LOCAL_SDK_DIR/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$LOCAL_SDK_DIR" "platform-tools" "platforms;android-34" "build-tools;34.0.0"

            echo "✅ Android SDK installed. Configuring Flutter..."
            export ANDROID_HOME="$LOCAL_SDK_DIR"
            export ANDROID_SDK_ROOT="$LOCAL_SDK_DIR"
            flutter config --android-sdk "$LOCAL_SDK_DIR"
            yes | flutter doctor --android-licenses || true
        else
            echo "ℹ️ Skipping automated Android SDK setup."
        fi
    fi
else
    echo "✅ Android SDK detected at $ANDROID_SDK_PATH"
fi

# 4. Sample Generation
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
