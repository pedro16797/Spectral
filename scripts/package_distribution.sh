#!/bin/bash

# Exit on error
set -e

# Check if flutter is in PATH
if ! command -v flutter &> /dev/null
then
    echo "❌ Error: 'flutter' command not found."
    echo "Please ensure Flutter SDK is installed and added to your PATH."
    exit 1
fi

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

# Detect Python in venv for the command
if [ -f ".venv/Scripts/python" ]; then
    VENV_PYTHON=".venv/Scripts/python"
elif [ -f ".venv/bin/python" ]; then
    VENV_PYTHON=".venv/bin/python"
else
    # Fallback to system python if venv not found
    if command -v python3 &> /dev/null; then
        VENV_PYTHON="python3"
    else
        VENV_PYTHON="python"
    fi
fi

$VENV_PYTHON scripts/generate_video.py "$DIST_DIR/videos_tmp"

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
