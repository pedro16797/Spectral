#!/bin/bash

# Exit on error
set -e

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
