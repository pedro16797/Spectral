#!/bin/bash
# Builds the full distribution bundle: Android APKs, web zip, store
# screenshots, and metadata, under distribution/v<VERSION>/.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "📦 Starting Spectral Distribution Packaging..."

# 1. Sync Version
echo "🏷️ Syncing version..."
bash scripts/sync_version.sh
VERSION=$(tr -d '[:space:]' < VERSION)

DIST_DIR="distribution/v${VERSION}"
mkdir -p "$DIST_DIR/android/phone" "$DIST_DIR/android/tablet" \
         "$DIST_DIR/ios/phone" "$DIST_DIR/ios/tablet" \
         "$DIST_DIR/web" "$DIST_DIR/metadata"

# 2. Android build
echo "🤖 Building Android App Bundle + APKs..."
bash scripts/build.sh android
cp build/app/outputs/bundle/release/app-release.aab "$DIST_DIR/android/spectral-${VERSION}.aab"
cp build/app/outputs/flutter-apk/app-*-release.apk "$DIST_DIR/android/"

# 3. Web build
echo "🌐 Building Web App..."
bash scripts/build.sh web
(cd build/web && zip -qr "../../$DIST_DIR/web/spectral-web.zip" .)

# 4. Screenshots.
# The play_file scenes need the sample assets, which are deliberately not in
# pubspec.yaml (they would bloat production builds), and the build must not
# fetch CanvasKit from a CDN or captures come out blank. Temporarily bundle
# the samples, build a capture-only web build, shoot, then restore.
echo "📸 Generating screenshots..."
cp pubspec.yaml pubspec.yaml.bak
trap 'mv -f pubspec.yaml.bak pubspec.yaml 2>/dev/null || true' EXIT
python3 - <<'EOF'
with open('pubspec.yaml') as f:
    text = f.read()
marker = '    - resources/locales/\n'
assert marker in text, 'pubspec assets block changed; update package_distribution.sh'
text = text.replace(
    marker,
    marker + '    - resources/samples/audio/\n    - resources/samples/rf/\n',
)
with open('pubspec.yaml', 'w') as f:
    f.write(text)
EOF
flutter build web --release --no-web-resources-cdn
python3 scripts/generate_screenshots.py "$DIST_DIR/screenshots_tmp"
mv -f pubspec.yaml.bak pubspec.yaml
trap - EXIT

cp "$DIST_DIR/screenshots_tmp/phone/"*.png "$DIST_DIR/android/phone/"
cp "$DIST_DIR/screenshots_tmp/phone_modern/"*.png "$DIST_DIR/ios/phone/"
cp "$DIST_DIR/screenshots_tmp/tablet_landscape/"*.png "$DIST_DIR/android/tablet/"
cp "$DIST_DIR/screenshots_tmp/tablet_portrait/"*.png "$DIST_DIR/ios/tablet/"
rm -rf "$DIST_DIR/screenshots_tmp"

# 5. Metadata
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
ls -R "$DIST_DIR"
