#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SIGN_IDENTITY="${MITTARI_SIGN_IDENTITY:-Developer ID Application}"
APP="$ROOT/build/Mittari.app"

swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/Mittari" "$APP/Contents/MacOS/Mittari"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Sparkle's own build embeds Sparkle.framework via Xcode's "Embed Frameworks" phase; here
# we copy it out of SwiftPM's artifact cache instead.
SPARKLE_FRAMEWORK="$(find "$BIN_DIR" -maxdepth 1 -type d -name "Sparkle.framework" | head -n 1)"
if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
    SPARKLE_FRAMEWORK="$(find "$ROOT/.build/artifacts" -type d -name "Sparkle.framework" | head -n 1)"
fi
if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
    echo "error: Sparkle.framework not found; run 'swift build' first" >&2
    exit 1
fi
rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
ditto "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"

# SwiftPM doesn't add an rpath for embedded frameworks, so Sparkle can't be found at launch
# without this.
if ! otool -l "$APP/Contents/MacOS/Mittari" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Mittari"
fi

# Ad-hoc identities (SIGN_IDENTITY=-, for local builds without a Developer ID cert) can't
# carry a secure timestamp, and under the hardened runtime their missing Team ID makes
# library validation reject the embedded Sparkle.framework at launch.
SIGN_FLAGS=(--force --sign "$SIGN_IDENTITY")
if [[ "$SIGN_IDENTITY" != "-" ]]; then
    SIGN_FLAGS+=(--options runtime --timestamp)
fi

# Sign inside-out, following Sparkle's documented order: its XPC services and helper
# tools first, then the framework itself, then the app.
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
for item in \
    "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc" \
    "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc" \
    "$FRAMEWORK/Versions/B/Autoupdate" \
    "$FRAMEWORK/Versions/B/Updater.app"; do
    [[ -e "$item" ]] && codesign "${SIGN_FLAGS[@]}" "$item"
done
codesign "${SIGN_FLAGS[@]}" "$FRAMEWORK"

codesign "${SIGN_FLAGS[@]}" "$APP"

echo "Built $APP"
