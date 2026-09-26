#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SIGN_IDENTITY="${MITTARI_SIGN_IDENTITY:-Apple Development: gabrielepartiti@outlook.com (CD2U989KNR)}"
APP="$ROOT/build/Mittari.app"

swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Mittari" "$APP/Contents/MacOS/Mittari"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP"

echo "Built $APP"
