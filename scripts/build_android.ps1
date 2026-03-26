# Build Android APK with optimizations (PowerShell)

# Detect project-local Android SDK
$LOCAL_SDK_DIR = Join-Path $PSScriptRoot '..\sdks\android'
if (!(Test-Path $LOCAL_SDK_DIR)) { $LOCAL_SDK_DIR = Join-Path $pwd 'sdks\android' }

if (Test-Path $LOCAL_SDK_DIR) {
    Write-Host "Using local Android SDK at $LOCAL_SDK_DIR" -ForegroundColor Cyan
    $env:ANDROID_HOME = $LOCAL_SDK_DIR
    $env:ANDROID_SDK_ROOT = $LOCAL_SDK_DIR
    $env:PATH = "$($env:PATH);$LOCAL_SDK_DIR\cmdline-tools\latest\bin;$LOCAL_SDK_DIR\platform-tools"
}

Write-Host 'Starting optimized Android build for Spectral...' -ForegroundColor Cyan

# Clean previous builds
Write-Host 'Cleaning previous builds...' -ForegroundColor Gray
flutter clean

# Get dependencies
Write-Host 'Getting dependencies...' -ForegroundColor Gray
flutter pub get

# Build APK with optimizations
Write-Host 'Building optimized APKs...' -ForegroundColor Cyan
flutter build apk --release `
    --split-per-abi `
    --obfuscate `
    --split-debug-info=build/app/outputs/debug-info

Write-Host 'Build complete!' -ForegroundColor Green
Write-Host 'APKs are located in: build/app/outputs/flutter-apk/' -ForegroundColor Cyan

# Display sizes
Write-Host 'APK Sizes:' -ForegroundColor Yellow
Get-ChildItem build/app/outputs/flutter-apk/app-*-release.apk | Select-Object Name, @{Name='Size(MB)';Expression={'{0:N2}' -f ($_.Length / 1MB)}}
