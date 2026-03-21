#!/bin/bash

# Exit on error
set -e

echo "🚀 Starting Web build for Spectral..."

# Clean previous builds
echo "🧹 Cleaning previous builds..."
flutter clean

# Get dependencies
echo "📦 Getting dependencies..."
flutter pub get

# Build Web
echo "🏗️ Building Web app..."
flutter build web --release

echo "✅ Build complete!"
echo "📁 Web build is located in: build/web/"
