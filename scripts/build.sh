#!/bin/bash
# Builds Spectral for one platform: build.sh <android|android-debug|web|ios>
#
# android:       release App Bundle (.aab, what the Play Store takes) plus
#                per-ABI APKs for sideload/QA — obfuscated, symbols split out.
# android-debug: single debug-signed APK for PR/QA installs.
# web:           release web bundle.
# ios:           release build without code signing (local integrity check).
set -euo pipefail
cd "$(dirname "$0")/.."

PLATFORM="${1:-}"

echo "🧹 Cleaning previous builds..."
flutter clean

echo "📦 Getting dependencies..."
flutter pub get

case "$PLATFORM" in
  android)
    echo "🏗️ Building release App Bundle..."
    flutter build appbundle --release \
        --obfuscate \
        --split-debug-info=build/app/outputs/debug-info-aab
    echo "🏗️ Building optimized APKs..."
    flutter build apk --release \
        --split-per-abi \
        --obfuscate \
        --split-debug-info=build/app/outputs/debug-info
    echo "✅ App Bundle: build/app/outputs/bundle/release/app-release.aab"
    echo "✅ APKs are in build/app/outputs/flutter-apk/:"
    ls -lh build/app/outputs/flutter-apk/app-*-release.apk
    ;;
  android-debug)
    echo "🏗️ Building debug APK..."
    flutter build apk --debug
    echo "✅ Debug APK: build/app/outputs/flutter-apk/app-debug.apk"
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
    echo "Usage: $0 <android|android-debug|web|ios>" >&2
    exit 1
    ;;
esac
