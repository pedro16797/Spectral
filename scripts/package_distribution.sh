#!/bin/bash

# Exit on error
set -e

echo "📦 Starting Spectral Distribution Packaging..."

# 1. Sync Version
echo "🏷️ Syncing version..."
chmod +x scripts/sync_version.sh
./scripts/sync_version.sh
VERSION=$(cat VERSION | tr -d '[:space:]')

# Define distribution folder
DIST_DIR="distribution/v${VERSION}"
mkdir -p "$DIST_DIR/android"
mkdir -p "$DIST_DIR/web"
mkdir -p "$DIST_DIR/screenshots"
mkdir -p "$DIST_DIR/metadata"

# 2. Run Android Build
echo "🤖 Building Android APKs..."
chmod +x scripts/build_android.sh
./scripts/build_android.sh
cp build/app/outputs/flutter-apk/app-*-release.apk "$DIST_DIR/android/"

# 3. Run Web Build
echo "🌐 Building Web App..."
chmod +x scripts/build_web.sh
./scripts/build_web.sh
# Create a zip of the web build
cd build/web
zip -r "../../$DIST_DIR/web/spectral-web.zip" .
cd ../..

# 4. Generate Screenshots
# Note: Screenshots require a debug web build as per memory
echo "📸 Generating screenshots..."
# We need to make sure the debug web build exists
flutter build web --debug
python3 scripts/generate_screenshots.py
cp resources/screenshots/*.png "$DIST_DIR/screenshots/"

# 5. Collect Metadata
echo "📝 Collecting metadata..."
cat <<EOF > "$DIST_DIR/metadata/info.json"
{
  "name": "Spectral",
  "version": "$VERSION",
  "build_date": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "description": "Spectral observation application for audio and RF data.",
  "platforms": ["Android", "Web", "iOS (Source Only)"]
}
EOF

# Copy changelog if it exists
if [ -f "CHANGELOG.md" ]; then
  cp CHANGELOG.md "$DIST_DIR/metadata/"
fi

echo "✅ Distribution bundle created successfully!"
echo "📁 Bundle location: $DIST_DIR"
echo "📊 Contents:"
ls -R "$DIST_DIR"
