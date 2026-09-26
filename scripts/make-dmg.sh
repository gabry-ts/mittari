#!/usr/bin/env bash
# Builds the app (if needed) and packages it as build/Mittari-<version>.dmg, with a link to
# /Applications for drag-and-drop install. Uses only tools that ship with macOS.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Mittari.app"
NAME="Mittari"

REBUILD=0
for arg in "$@"; do
    case "$arg" in
        --rebuild) REBUILD=1 ;;
    esac
done

if [[ ! -d "$APP" || "$REBUILD" -eq 1 ]]; then
    "$ROOT/scripts/build.sh"
fi

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
DMG="$ROOT/build/$NAME-$VERSION.dmg"
# A fresh staging folder in the temporary directory, which macOS cleans up on its own.
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/mittari-dmg.XXXXXX")"

ditto "$APP" "$STAGING/$NAME.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create -quiet -volname "$NAME $VERSION" -srcfolder "$STAGING" \
    -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG"

hdiutil verify -quiet "$DMG"
echo "Built $DMG ($(du -h "$DMG" | cut -f1 | xargs))"
