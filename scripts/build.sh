#!/bin/bash
# Build Boulder.app for local testing.
#   1. brew install xcodegen if missing
#   2. xcodegen generate
#   3. xcodebuild Release
#   4. Surface the .app path

set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Installing xcodegen via Homebrew…"
  brew install xcodegen
fi

xcodegen generate

xcodebuild \
  -project Boulder.xcodeproj \
  -scheme Boulder \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_REQUIRED=NO \
  build 2>&1 | tail -25

APP="$(find build -type d -name 'Boulder.app' -path '*Build/Products/Release/*' | head -1)"
if [ -n "$APP" ]; then
  echo ""
  echo "✓ Built:"
  echo "  $APP"
  echo ""
  echo "Move it to /Applications and launch — Boulder lives in your menubar."
fi
