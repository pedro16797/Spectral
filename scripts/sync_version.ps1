# Sync Version from VERSION file to pubspec.yaml (PowerShell)

$VERSION_FILE = 'VERSION'
$PUBSPEC_FILE = 'pubspec.yaml'

if (!(Test-Path $VERSION_FILE)) {
    Write-Host 'Error: VERSION file is missing.' -ForegroundColor Red
    exit 1
}

$VERSION = (Get-Content $VERSION_FILE).Trim()

if ([string]::IsNullOrWhiteSpace($VERSION)) {
    Write-Host 'Error: VERSION file is empty.' -ForegroundColor Red
    exit 1
}

Write-Host "Syncing version $VERSION to $PUBSPEC_FILE..." -ForegroundColor Cyan

# Update version in pubspec.yaml
(Get-Content $PUBSPEC_FILE) -replace '^version: .*', "version: $VERSION" | Set-Content $PUBSPEC_FILE

Write-Host "pubspec.yaml updated to version $VERSION" -ForegroundColor Green
