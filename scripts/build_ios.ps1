# Build iOS (PowerShell stub for cross-platform consistency)

Write-Host "🍎 Starting iOS build for Spectral..." -ForegroundColor Cyan

if ($IsMacOS -or $env:OSTYPE -like "darwin*") {
    # Clean previous builds
    Write-Host "🧹 Cleaning previous builds..." -ForegroundColor Gray
    flutter clean

    # Get dependencies
    Write-Host "📦 Getting dependencies..." -ForegroundColor Gray
    flutter pub get

    # Strip sample assets from pubspec.yaml (macOS version)
    Write-Host "✂️ Stripping sample assets for production build..." -ForegroundColor Gray
    grep -v "\- resources/samples/" pubspec.yaml > pubspec.yaml.tmp && mv pubspec.yaml.tmp pubspec.yaml
    Remove-Item -Recurse -Force resources/samples/

    # Build iOS
    Write-Host "🏗️ Building iOS app (No-Codesign)..." -ForegroundColor Cyan
    flutter build ios --release --no-codesign

    Write-Host "✅ Build complete!" -ForegroundColor Green
    Write-Host "📁 iOS build is located in: build/ios/iphoneos/" -ForegroundColor Cyan
} else {
    Write-Host "❌ Error: iOS builds require macOS and Xcode." -ForegroundColor Red
    exit 1
}
