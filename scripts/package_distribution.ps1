# Spectral Distribution Packaging (PowerShell)

Write-Host "📦 Starting Spectral Distribution Packaging..." -ForegroundColor Green

# Detect project-local Android SDK
$LOCAL_SDK_DIR = "$PSScriptRoot\..\sdks\android"
if (!(Test-Path $LOCAL_SDK_DIR)) { $LOCAL_SDK_DIR = "$pwd\sdks\android" }

if (Test-Path $LOCAL_SDK_DIR) {
    Write-Host "🤖 Using local Android SDK at $LOCAL_SDK_DIR" -ForegroundColor Cyan
    $env:ANDROID_HOME = $LOCAL_SDK_DIR
    $env:ANDROID_SDK_ROOT = $LOCAL_SDK_DIR
    $env:PATH = "$($env:PATH);$LOCAL_SDK_DIR\cmdline-tools\latest\bin;$LOCAL_SDK_DIR\platform-tools"
}

# 1. Sync Version
Write-Host "🏷️ Syncing version..." -ForegroundColor Gray
& powershell -ExecutionPolicy Bypass -File .\scripts\sync_version.ps1
$VERSION = (Get-Content VERSION).Trim()

# Define distribution folder
$DIST_DIR = "distribution\v$VERSION"
New-Item -ItemType Directory -Force -Path "$DIST_DIR\android\phone" | Out-Null
New-Item -ItemType Directory -Force -Path "$DIST_DIR\android\tablet" | Out-Null
New-Item -ItemType Directory -Force -Path "$DIST_DIR\ios\phone" | Out-Null
New-Item -ItemType Directory -Force -Path "$DIST_DIR\ios\tablet" | Out-Null
New-Item -ItemType Directory -Force -Path "$DIST_DIR\web" | Out-Null
New-Item -ItemType Directory -Force -Path "$DIST_DIR\metadata" | Out-Null

# 2. Run Android Build
Write-Host "🤖 Building Android APKs..." -ForegroundColor Gray
& powershell -ExecutionPolicy Bypass -File .\scripts\build_android.ps1
Copy-Item "build\app\outputs\flutter-apk\app-*-release.apk" "$DIST_DIR\android\"

# 3. Run Web Build
Write-Host "🌐 Building Web App..." -ForegroundColor Gray
& powershell -ExecutionPolicy Bypass -File .\scripts\build_web.ps1
# Create a zip of the web build
Compress-Archive -Path "build\web\*" -DestinationPath "$DIST_DIR\web\spectral-web.zip" -Force

# 4. Generate Screenshots
Write-Host "📸 Generating screenshots..." -ForegroundColor Gray
flutter build web --debug
if (Test-Path ".venv\Scripts\python.exe") {
    & .venv\Scripts\python.exe scripts\generate_screenshots.py "$DIST_DIR\screenshots_tmp"
} else {
    python scripts\generate_screenshots.py "$DIST_DIR\screenshots_tmp"
}

# Distribute screenshots
Copy-Item "$DIST_DIR\screenshots_tmp\phone\*.png" "$DIST_DIR\android\phone\"
Copy-Item "$DIST_DIR\screenshots_tmp\phone_modern\*.png" "$DIST_DIR\ios\phone\"
Copy-Item "$DIST_DIR\screenshots_tmp\tablet_landscape\*.png" "$DIST_DIR\android\tablet\"
Copy-Item "$DIST_DIR\screenshots_tmp\tablet_portrait\*.png" "$DIST_DIR\ios\tablet\"
Remove-Item -Recurse -Force "$DIST_DIR\screenshots_tmp"

# 5. Generate App Store Videos
Write-Host "🎥 Generating app store videos..." -ForegroundColor Gray
if (Test-Path ".venv\Scripts\python.exe") {
    $VENV_PYTHON = ".venv\Scripts\python.exe"
} else {
    $VENV_PYTHON = "python"
}
& $VENV_PYTHON scripts\generate_video.py "$DIST_DIR\videos_tmp"

# Distribute videos
Copy-Item "$DIST_DIR\videos_tmp\phone\app_preview.webm" "$DIST_DIR\android\phone\"
Copy-Item "$DIST_DIR\videos_tmp\tablet\app_preview.webm" "$DIST_DIR\android\tablet\"

if (Test-Path "$DIST_DIR\videos_tmp\phone\app_preview.mp4") {
    Copy-Item "$DIST_DIR\videos_tmp\phone\app_preview.mp4" "$DIST_DIR\ios\phone\"
}
if (Test-Path "$DIST_DIR\videos_tmp\tablet\app_preview.mp4") {
    Copy-Item "$DIST_DIR\videos_tmp\tablet\app_preview.mp4" "$DIST_DIR\ios\tablet\"
}
Remove-Item -Recurse -Force "$DIST_DIR\videos_tmp"

# 6. Collect Metadata
Write-Host "📝 Collecting metadata..." -ForegroundColor Gray
$DATE = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
$INFO = @"
{
  "name": "Spectral",
  "version": "$VERSION",
  "build_date": "$DATE",
  "description": "Spectral observation application for audio and RF data.",
  "platforms": ["Android", "Web", "iOS (Source Only)"],
  "store_links": {
    "playstore": "TBD",
    "appstore": "TBD"
  }
}
"@
$INFO | Out-File -FilePath "$DIST_DIR\metadata\info.json"

Write-Host "✅ Distribution bundle created successfully!" -ForegroundColor Green
Write-Host "📁 Bundle location: $DIST_DIR" -ForegroundColor Cyan
