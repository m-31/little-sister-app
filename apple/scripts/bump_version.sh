#!/usr/bin/env bash
#
# Sets MARKETING_VERSION to the version you name and increments
# CURRENT_PROJECT_VERSION (the build number) by one.
#
# Both settings exist once per configuration per target — six copies each — and
# the release tooling requires every copy to agree. Editing them by hand, or
# through Xcode's General tab (which only covers the one target selected), is
# how they drift; this is the reliable route.
#
# It deliberately does NOT touch the CHANGELOG, commit, or tag. The release
# preparation script rolls the notes and commits; tagging happens later. This
# does one thing, so it can be run and inspected on its own.
#
# Usage: scripts/bump_version.sh <new-version>
#
#   scripts/bump_version.sh 0.2.1

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."   # -> apple/

PBXPROJ="LittleSister.xcodeproj/project.pbxproj"

die() { echo "error: $*" >&2; exit 1; }

# Reads one build setting and insists every copy of it already agrees.
#
# A disagreement is exactly the condition this script exists to prevent, so it
# refuses rather than silently overwriting: if the six copies differ, one of
# them was edited on purpose and picking a winner would discard that intent
# without telling anyone.
read_unique() {
  local setting="$1" values
  values="$(sed -n "s/.*$setting = \(.*\);/\1/p" "$PBXPROJ" | sort -u)"
  [ -n "$values" ] || die "no $setting in $PBXPROJ."
  if [ "$(printf '%s\n' "$values" | wc -l)" -ne 1 ]; then
    echo "error: $setting is inconsistent across configurations:" >&2
    printf '%s\n' "$values" | sed 's/^/       /' >&2
    echo "       Set every configuration to the same value, then re-run." >&2
    exit 1
  fi
  printf '%s' "$values"
}

[ $# -eq 1 ] || die "usage: ${BASH_SOURCE[0]##*/} <new-version>   (e.g. 0.2.1)"
NEW_VERSION="$1"
[[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || die "'$NEW_VERSION' is not a three-part version (expected e.g. 0.2.1)."
[ -f "$PBXPROJ" ] || die "$PBXPROJ not found (run this from anywhere; it cd's to apple/)."

OLD_VERSION="$(read_unique MARKETING_VERSION)"
OLD_BUILD="$(read_unique CURRENT_PROJECT_VERSION)"
[[ "$OLD_BUILD" =~ ^[0-9]+$ ]] \
  || die "CURRENT_PROJECT_VERSION is '$OLD_BUILD', which is not a number to increment."

# Refuse anything that isn't a step forward. A downgrade is almost always a typo,
# and it would collide with a tag that already exists.
[ "$NEW_VERSION" != "$OLD_VERSION" ] || die "MARKETING_VERSION is already $NEW_VERSION."
if [ "$(printf '%s\n%s\n' "$OLD_VERSION" "$NEW_VERSION" | sort -V | head -1)" != "$OLD_VERSION" ]; then
  die "$NEW_VERSION is lower than the current $OLD_VERSION."
fi

NEW_BUILD=$((OLD_BUILD + 1))

# Rewrite via a temp file, then copy the contents back, so a failure mid-write
# cannot leave a half-edited project file — and so the original's permissions
# are preserved (which `mv` would replace with the temp file's).
TMP="$(mktemp "${TMPDIR:-/tmp}/bump_version.XXXXXX")"
trap 'rm -f "$TMP"' EXIT
sed -e "s/MARKETING_VERSION = .*;/MARKETING_VERSION = $NEW_VERSION;/" \
    -e "s/CURRENT_PROJECT_VERSION = .*;/CURRENT_PROJECT_VERSION = $NEW_BUILD;/" \
    "$PBXPROJ" > "$TMP"
cat "$TMP" > "$PBXPROJ"

# Verify what was actually written rather than assuming the sed did what it said.
FINAL_VERSION="$(read_unique MARKETING_VERSION)"
FINAL_BUILD="$(read_unique CURRENT_PROJECT_VERSION)"
[ "$FINAL_VERSION" = "$NEW_VERSION" ] || die "MARKETING_VERSION ended up at $FINAL_VERSION, not $NEW_VERSION."
[ "$FINAL_BUILD" = "$NEW_BUILD" ] || die "CURRENT_PROJECT_VERSION ended up at $FINAL_BUILD, not $NEW_BUILD."

echo "MARKETING_VERSION        $OLD_VERSION -> $NEW_VERSION"
echo "CURRENT_PROJECT_VERSION  $OLD_BUILD -> $NEW_BUILD"
echo
echo "Next: write the consumer-facing notes under '## [Unreleased]' in the"
echo "CHANGELOG, then run the release preparation script."
