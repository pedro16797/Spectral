#!/bin/bash

# Exit on error
set -e

echo "🚀 Starting iOS build for Spectral (No Codesign)..."

# Clean previous builds
echo "🧹 Cleaning previous builds..."
flutter clean

# Get dependencies
echo "📦 Getting dependencies..."
flutter pub get

# Build iOS (No-Codesign for local integrity check)
echo "🏗️ Building iOS app..."
flutter build ios --release --no-codesign

echo "✅ Build complete!"
echo "📁 iOS App Bundle is located in: build/ios/iphoneos/Runner.app"
