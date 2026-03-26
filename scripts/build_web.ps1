# Build Web release (PowerShell)

Write-Host 'Starting Web build for Spectral...' -ForegroundColor Cyan

# Clean previous builds
Write-Host 'Cleaning previous builds...' -ForegroundColor Gray
flutter clean

# Get dependencies
Write-Host 'Getting dependencies...' -ForegroundColor Gray
flutter pub get

# Build Web
Write-Host 'Building Web app...' -ForegroundColor Cyan
flutter build web --release

Write-Host 'Build complete!' -ForegroundColor Green
Write-Host 'Web build is located in: build/web/' -ForegroundColor Cyan
