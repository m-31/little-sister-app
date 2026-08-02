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
# DMG matches the release tag.
#
# Every configuration of every target must agree — that is the contract
# release_prep.sh enforces, and it is enforced identically here. An earlier
# version of this script took `| head -1` of the sorted set, which silently
# picked the *lowest* value when they disagreed: bumping only the app target
# produced a DMG still named for the previous version, with no warning. A
# wrongly-named release artifact is worse than a failed build.
VERSION="$(sed -n 's/.*MARKETING_VERSION = \(.*\);/\1/p' LittleSister.xcodeproj/project.pbxproj | sort -u)"
if [ -z "$VERSION" ]; then
  echo "error: no MARKETING_VERSION in LittleSister.xcodeproj/project.pbxproj." >&2
  exit 1
fi
if [ "$(printf '%s\n' "$VERSION" | wc -l)" -ne 1 ]; then
  echo "error: MARKETING_VERSION is inconsistent across configurations:" >&2
  printf '%s\n' "$VERSION" >&2
  echo "       Set every target's version (app, tests, UI tests) to the same value." >&2
  exit 1
fi

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

# Refuse to ship a binary carrying code-coverage instrumentation.
#
# ENABLE_CODE_COVERAGE defaults to YES, and building *through a scheme* whose
# app target is marked buildForTesting turns that default into real
# instrumentation (CLANG_COVERAGE_MAPPING -> `-profile-generate`), even for
# -configuration Release. The project's Release configuration now sets
# ENABLE_CODE_COVERAGE = NO, but that is a setting someone can silently undo,
# and an instrumented binary looks completely normal from the outside — it just
# runs slower and writes .profraw files on the recipient's Mac. So verify the
# artifact rather than trusting the setting.
#
# Written to fail closed: a guard that silently passes when it cannot read the
# binary is worse than no guard, because it reads as a clean result.
BINARY="$APP_PATH/Contents/MacOS/$SCHEME"
if [ ! -f "$BINARY" ]; then
  echo "error: built binary not found at $BINARY" >&2
  exit 1
fi
if ! load_commands="$(otool -l "$BINARY")"; then
  echo "error: could not read load commands from $BINARY — cannot verify it." >&2
  exit 1
fi
if grep -q "__llvm_prf" <<<"$load_commands"; then
  echo "error: $SCHEME.app is instrumented for code coverage — refusing to package it." >&2
  echo "       Check ENABLE_CODE_COVERAGE in the Release build configuration." >&2
  exit 1
fi

# Stage the app alongside an Applications symlink so the mounted DMG shows
# both side by side (the standard drag-to-install layout). `ditto`, not
# `cp -R`, is Apple's recommended way to copy an .app bundle — it preserves
# the symlinks and metadata a bundle's code signature depends on.
ditto "$APP_PATH" "$STAGING_DIR/$SCHEME.app"
ln -s /Applications "$STAGING_DIR/Applications"

DMG_PATH="$OUTPUT_DIR/$SCHEME-$VERSION.dmg"
rm -f "$DMG_PATH"

echo "Packaging $STAGING_DIR -> $DMG_PATH"
hdiutil create -volname "Little Sister" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"

echo "Done: $DMG_PATH"
