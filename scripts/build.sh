#!/bin/bash
# Builds Spectral for one platform: build.sh <android|web|ios>
#
# android: release APKs split per ABI, obfuscated, debug symbols split out.
# web:     release web bundle.
# ios:     release build without code signing (local integrity check).
set -euo pipefail
cd "$(dirname "$0")/.."

PLATFORM="${1:-}"

echo "🧹 Cleaning previous builds..."
flutter clean

echo "📦 Getting dependencies..."
flutter pub get

case "$PLATFORM" in
  android)
    echo "🏗️ Building optimized APKs..."
    flutter build apk --release \
        --split-per-abi \
        --obfuscate \
        --split-debug-info=build/app/outputs/debug-info
    echo "✅ APKs are in build/app/outputs/flutter-apk/:"
    ls -lh build/app/outputs/flutter-apk/app-*-release.apk
    ;;
  web)
    echo "🏗️ Building Web app..."
    flutter build web --release
    echo "✅ Web build is in build/web/"
    ;;
  ios)
    echo "🏗️ Building iOS app (no codesign)..."
    flutter build ios --release --no-codesign
    echo "✅ iOS app bundle is in build/ios/iphoneos/Runner.app"
    ;;
  *)
    echo "Usage: $0 <android|web|ios>" >&2
    exit 1
    ;;
esac
