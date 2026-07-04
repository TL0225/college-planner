#!/usr/bin/env bash
# Run toolbar architecture, accessibility, and visual regression tests.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DERIVED="${DERIVED:-/tmp/CollegeToolbarTestsDD}"
DEST="${DEST:-platform=macOS}"
cd "$ROOT"

"$SCRIPT_DIR/college-xcodebuild-test.sh" \
  -scheme College \
  -destination "$DEST" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  test \
  -only-testing:CollegeTests/ToolbarArchitectureTests \
  -only-testing:CollegeTests/GlassToolbarAccessibilityTests \
  -only-testing:CollegeTests/ToolbarVisualTests
