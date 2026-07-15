#!/usr/bin/env bash
#
# Builds a Release LittleSister.app and packages it into a distributable
# .dmg. See ../README.md "Distribution (DMG)" for what this does and does
# not cover (no Developer ID signing, no notarization).
#
# The DMG contains the app plus an "Applications" symlink, so whoever opens
# it gets the standard one-drag "drop the app onto Applications" install —
# that drag step itself is normal Finder DMG behavior and isn't something a
# build script can do on the recipient's Mac.
#
# Usage: scripts/make_dmg.sh [output-dir]
#   output-dir defaults to apple/dist/

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."   # -> apple/

SCHEME="LittleSister"
CONFIGURATION="Release"
OUTPUT_DIR="${1:-dist}"

# Name the artifact from the single-source version (MARKETING_VERSION) so the
# DMG matches the release tag; fall back to an unversioned name if unreadable.
VERSION="$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' LittleSister.xcodeproj/project.pbxproj | sort -u | head -1)"

DERIVED_DATA_DIR="$(mktemp -d)"
STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$DERIVED_DATA_DIR" "$STAGING_DIR"' EXIT

mkdir -p "$OUTPUT_DIR"

echo "Building $SCHEME ($CONFIGURATION)..."
xcodebuild \
  -project LittleSister.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  build

APP_PATH="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$SCHEME.app"
if [ ! -d "$APP_PATH" ]; then
  echo "error: built app not found at $APP_PATH" >&2
  exit 1
fi

# Stage the app alongside an Applications symlink so the mounted DMG shows
# both side by side (the standard drag-to-install layout). `ditto`, not
# `cp -R`, is Apple's recommended way to copy an .app bundle — it preserves
# the symlinks and metadata a bundle's code signature depends on.
ditto "$APP_PATH" "$STAGING_DIR/$SCHEME.app"
ln -s /Applications "$STAGING_DIR/Applications"

DMG_PATH="$OUTPUT_DIR/$SCHEME${VERSION:+-$VERSION}.dmg"
rm -f "$DMG_PATH"

echo "Packaging $STAGING_DIR -> $DMG_PATH"
hdiutil create -volname "Little Sister" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"

echo "Done: $DMG_PATH"
