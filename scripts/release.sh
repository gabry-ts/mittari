#!/usr/bin/env bash
# Full release pipeline: build, sign, package as a DMG, notarize, staple, and generate the
# appcast entry for this version. Used by CI (.github/workflows/release.yml) and runnable
# locally, except notarization and the appcast signing need real credentials:
#
#   MITTARI_SIGN_IDENTITY   codesign identity (defaults to "Developer ID Application")
#   ASC_API_KEY_PATH        path to the App Store Connect API key .p8 file
#   ASC_API_KEY_ID          App Store Connect API key ID
#   ASC_API_ISSUER_ID       App Store Connect API issuer ID
#   SPARKLE_ED_KEY_FILE     path to a file holding the raw Sparkle EdDSA private key
#   SPARKLE_ED_PRIVATE_KEY  the raw Sparkle EdDSA private key itself, used instead of
#                           SPARKLE_ED_KEY_FILE for local runs
#   SPARKLE_VERSION         Sparkle release matching Package.swift's, e.g. 2.10.0
#                           (defaults to whatever Package.swift pins)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NAME="Mittari"
REPO="gabry-ts/mittari"
APP="$ROOT/build/$NAME.app"

echo "==> Building"
"$ROOT/scripts/build.sh"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
DMG="$ROOT/build/$NAME-$VERSION.dmg"

echo "==> Packaging $VERSION"
"$ROOT/scripts/make-dmg.sh" --rebuild

: "${ASC_API_KEY_PATH:?Set ASC_API_KEY_PATH to the App Store Connect API key .p8 file}"
: "${ASC_API_KEY_ID:?Set ASC_API_KEY_ID}"
: "${ASC_API_ISSUER_ID:?Set ASC_API_ISSUER_ID}"

echo "==> Notarizing $DMG"
xcrun notarytool submit "$DMG" \
    --key "$ASC_API_KEY_PATH" --key-id "$ASC_API_KEY_ID" --issuer "$ASC_API_ISSUER_ID" \
    --wait

echo "==> Stapling"
xcrun stapler staple "$DMG"

SPARKLE_KEY_FILE="${SPARKLE_ED_KEY_FILE:-}"
if [[ -z "$SPARKLE_KEY_FILE" ]]; then
    : "${SPARKLE_ED_PRIVATE_KEY:?Set SPARKLE_ED_KEY_FILE or SPARKLE_ED_PRIVATE_KEY}"
    SPARKLE_KEY_FILE="$(mktemp)"
    trap 'rm -f "$SPARKLE_KEY_FILE"' EXIT
    printf '%s' "$SPARKLE_ED_PRIVATE_KEY" > "$SPARKLE_KEY_FILE"
fi

SPARKLE_VERSION="${SPARKLE_VERSION:-$(sed -n 's/.*sparkle-project\/Sparkle.*from: *"\([0-9.]*\)".*/\1/p' "$ROOT/Package.swift" | head -n 1)}"
: "${SPARKLE_VERSION:?Could not determine the Sparkle version; set SPARKLE_VERSION}"

echo "==> Fetching Sparkle $SPARKLE_VERSION tools"
TOOLS_DIR="$ROOT/build/sparkle-tools"
if [[ ! -x "$TOOLS_DIR/bin/generate_appcast" ]]; then
    rm -rf "$TOOLS_DIR"
    mkdir -p "$TOOLS_DIR"
    curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
        -o "$ROOT/build/sparkle-tools.tar.xz"
    tar -xJf "$ROOT/build/sparkle-tools.tar.xz" -C "$TOOLS_DIR"
    chmod +x "$TOOLS_DIR/bin/generate_appcast"
fi

echo "==> Generating the appcast"
APPCAST_INPUT="$ROOT/build/appcast-input"
rm -rf "$APPCAST_INPUT"
mkdir -p "$APPCAST_INPUT"
cp "$DMG" "$APPCAST_INPUT/"
for ext in md html; do
    NOTES="$ROOT/docs/release-notes/$VERSION.$ext"
    if [[ -f "$NOTES" ]]; then
        cp "$NOTES" "$APPCAST_INPUT/$NAME-$VERSION.$ext"
        break
    fi
done

"$TOOLS_DIR/bin/generate_appcast" \
    --ed-key-file "$SPARKLE_KEY_FILE" \
    --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
    -o "$ROOT/build/appcast.xml" \
    "$APPCAST_INPUT"

echo "==> Done"
echo "  $DMG"
echo "  $ROOT/build/appcast.xml"
