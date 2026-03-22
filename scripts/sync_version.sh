#!/bin/bash

# Exit on error
set -e

# Read the version from the VERSION file
VERSION=$(cat VERSION | tr -d '[:space:]')

if [ -z "$VERSION" ]; then
  echo "❌ Error: VERSION file is empty or missing."
  exit 1
fi

echo "🔄 Syncing version $VERSION to pubspec.yaml..."

# Update the version in pubspec.yaml
# Uses a robust regex to find the 'version: ' line and replace the value
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS sed
  sed -i '' "s/^version: .*/version: $VERSION/" pubspec.yaml
else
  # Linux sed
  sed -i "s/^version: .*/version: $VERSION/" pubspec.yaml
fi

echo "✅ pubspec.yaml updated to version $VERSION"
