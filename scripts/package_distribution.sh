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
mkdir -p "$DIST_DIR/android/phone"
mkdir -p "$DIST_DIR/android/tablet"
mkdir -p "$DIST_DIR/ios/phone"
mkdir -p "$DIST_DIR/ios/tablet"
mkdir -p "$DIST_DIR/web"
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
echo "📸 Generating screenshots..."
# Build debug web for screenshots
flutter build web --debug
# Generate screenshots and organize them into platform subdirectories
python3 scripts/generate_screenshots.py "$DIST_DIR/screenshots_tmp"

# Distribute screenshots into platform folders
cp "$DIST_DIR/screenshots_tmp/phone/"*.png "$DIST_DIR/android/phone/"
cp "$DIST_DIR/screenshots_tmp/phone_modern/"*.png "$DIST_DIR/ios/phone/"
cp "$DIST_DIR/screenshots_tmp/tablet_landscape/"*.png "$DIST_DIR/android/tablet/"
cp "$DIST_DIR/screenshots_tmp/tablet_portrait/"*.png "$DIST_DIR/ios/tablet/"
rm -rf "$DIST_DIR/screenshots_tmp"

# 5. Generate App Store Videos
echo "🎥 Generating app store videos..."
python3 scripts/generate_video.py "$DIST_DIR/videos_tmp"

# Distribute videos into platform folders
# Android supports WebM
cp "$DIST_DIR/videos_tmp/phone/app_preview.webm" "$DIST_DIR/android/phone/"
cp "$DIST_DIR/videos_tmp/tablet/app_preview.webm" "$DIST_DIR/android/tablet/"

# iOS REQUIRES MP4 (H.264)
if [ -f "$DIST_DIR/videos_tmp/phone/app_preview.mp4" ]; then
  cp "$DIST_DIR/videos_tmp/phone/app_preview.mp4" "$DIST_DIR/ios/phone/"
else
  echo "⚠️ MP4 not found for phone, falling back to WebM (not App Store compliant)"
  cp "$DIST_DIR/videos_tmp/phone/app_preview.webm" "$DIST_DIR/ios/phone/"
fi

if [ -f "$DIST_DIR/videos_tmp/tablet/app_preview.mp4" ]; then
  cp "$DIST_DIR/videos_tmp/tablet/app_preview.mp4" "$DIST_DIR/ios/tablet/"
else
  echo "⚠️ MP4 not found for tablet, falling back to WebM (not App Store compliant)"
  cp "$DIST_DIR/videos_tmp/tablet/app_preview.webm" "$DIST_DIR/ios/tablet/"
fi

rm -rf "$DIST_DIR/videos_tmp"

# 6. Collect Metadata
echo "📝 Collecting metadata..."
cat <<EOF > "$DIST_DIR/metadata/info.json"
{
  "name": "Spectral",
  "version": "$VERSION",
  "build_date": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "description": "Spectral observation application for audio and RF data.",
  "platforms": ["Android", "Web", "iOS (Source Only)"],
  "store_links": {
    "playstore": "TBD",
    "appstore": "TBD"
  }
}
EOF

echo "✅ Distribution bundle created successfully!"
echo "📁 Bundle location: $DIST_DIR"
echo "📊 Contents:"
ls -R "$DIST_DIR"
