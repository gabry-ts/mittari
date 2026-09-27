#!/usr/bin/env bash
# Builds the app (if needed) and packages it as build/Mittari-<version>.dmg, with the app
# icon on a custom background next to a link to /Applications for drag-and-drop install.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Mittari.app"
NAME="Mittari"
SIGN_IDENTITY="${MITTARI_SIGN_IDENTITY:-Developer ID Application}"

REBUILD=0
for arg in "$@"; do
    case "$arg" in
        --rebuild) REBUILD=1 ;;
    esac
done

if [[ ! -d "$APP" || "$REBUILD" -eq 1 ]]; then
    "$ROOT/scripts/build.sh"
fi

if ! command -v create-dmg >/dev/null 2>&1; then
    echo "error: create-dmg not found; install it with 'brew install create-dmg'" >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
DMG="$ROOT/build/$NAME-$VERSION.dmg"
rm -f "$DMG"

# create-dmg only takes one background image; the higher-resolution Resources/dmg/background@2x.png
# is kept alongside it for anyone assembling the layout by hand in Finder instead.
create-dmg \
    --volname "$NAME $VERSION" \
    --background "$ROOT/Resources/dmg/background.png" \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "$NAME.app" 150 190 \
    --app-drop-link 450 190 \
    --hide-extension "$NAME.app" \
    --no-internet-enable \
    "$DMG" \
    "$APP"

SIGN_FLAGS=(--force --sign "$SIGN_IDENTITY")
[[ "$SIGN_IDENTITY" != "-" ]] && SIGN_FLAGS+=(--timestamp)
codesign "${SIGN_FLAGS[@]}" "$DMG"

hdiutil verify -quiet "$DMG"
echo "Built $DMG ($(du -h "$DMG" | cut -f1 | xargs))"
