#!/usr/bin/env bash
#
# Builds and runs the unit test suite from the command line, so the gate can be
# run without opening Xcode. This is the same invocation the release tooling
# uses, kept deliberately identical so a green run here means a green run there.
#
# Usage: scripts/run_tests.sh [extra xcodebuild args...]
#
#   scripts/run_tests.sh                        # whole suite
#   scripts/run_tests.sh -only-testing:LittleSisterTests/FailureTaxonomyTests
#   scripts/run_tests.sh -quiet                 # less build noise
#
# Exits non-zero if anything fails to build or any test fails.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."   # -> apple/

SCHEME="LittleSister"

# LittleSisterUITests is excluded on purpose: its stock testExample asserts
# nothing and flakes on XCUITest teardown for a menu-bar (agent) app. The
# release tooling skips it the same way; whether to write a real UI smoke test
# or delete the target is still open.
xcodebuild \
  -project LittleSister.xcodeproj \
  -scheme "$SCHEME" \
  -destination 'platform=macOS' \
  -skip-testing:LittleSisterUITests \
  "$@" \
  test
