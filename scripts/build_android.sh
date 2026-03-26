#!/bin/bash

# Exit on error
set -e

# Detect project-local Android SDK
LOCAL_SDK_DIR="$(pwd)/sdks/android"
if [ -d "$LOCAL_SDK_DIR" ]; then
    # Convert path to Windows format if on Windows (Git Bash, WSL, etc.)
    if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || command -v cygpath &> /dev/null; then
        WINDOWS_SDK_PATH=$(cygpath -w "$LOCAL_SDK_DIR")
        echo "🤖 Using local Android SDK at $WINDOWS_SDK_PATH"
        export ANDROID_HOME="$WINDOWS_SDK_PATH"
        export ANDROID_SDK_ROOT="$WINDOWS_SDK_PATH"
    elif [[ "$OS" == "Windows_NT" ]]; then
        # Fallback for some shells that set OS but not OSTYPE correctly
        WINDOWS_SDK_PATH=$(pwd -W 2>/dev/null || echo "$LOCAL_SDK_DIR")
        echo "🤖 Using local Android SDK at $WINDOWS_SDK_PATH"
        export ANDROID_HOME="$WINDOWS_SDK_PATH"
        export ANDROID_SDK_ROOT="$WINDOWS_SDK_PATH"
    else
        echo "🤖 Using local Android SDK at $LOCAL_SDK_DIR"
        export ANDROID_HOME="$LOCAL_SDK_DIR"
        export ANDROID_SDK_ROOT="$LOCAL_SDK_DIR"
    fi
    export PATH="$PATH:$LOCAL_SDK_DIR/cmdline-tools/latest/bin:$LOCAL_SDK_DIR/platform-tools"
fi

echo "🚀 Starting optimized Android build for Spectral..."

# Clean previous builds
echo "🧹 Cleaning previous builds..."
flutter clean

# Get dependencies
echo "📦 Getting dependencies..."
flutter pub get

# Build APK with optimizations
# --split-per-abi: Creates separate APKs for each architecture, significantly reducing download size per user.
# --obfuscate: Obfuscates Dart code to reduce size and improve security.
# --split-debug-info: Moves debug symbols out of the APK to a separate directory.
echo "🏗️ Building optimized APKs..."
flutter build apk --release \
    --split-per-abi \
    --obfuscate \
    --split-debug-info=build/app/outputs/debug-info

echo "✅ Build complete!"
echo "📁 APKs are located in: build/app/outputs/flutter-apk/"

# Display sizes
echo "📊 APK Sizes:"
ls -lh build/app/outputs/flutter-apk/app-*-release.apk
