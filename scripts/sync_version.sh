#!/bin/bash
# Syncs the version in pubspec.yaml from the root VERSION file.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(tr -d '[:space:]' < VERSION)

# Validate before feeding it to sed: a malformed VERSION would otherwise
# corrupt pubspec.yaml silently.
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(\+[0-9]+)?$ ]]; then
  echo "❌ Error: VERSION must look like 1.2.3+4 (got: '$VERSION')." >&2
  exit 1
fi

echo "🔄 Syncing version $VERSION to pubspec.yaml..."

if [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' "s/^version: .*/version: $VERSION/" pubspec.yaml
else
  sed -i "s/^version: .*/version: $VERSION/" pubspec.yaml
fi

echo "✅ pubspec.yaml updated to version $VERSION"
