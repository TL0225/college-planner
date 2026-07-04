#!/usr/bin/env bash
# Delete and re-seed ToolbarVisual snapshot baselines.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SNAPSHOT_DIR="$ROOT/CollegeTests/__Snapshots__/ToolbarVisual"
DERIVED="${DERIVED:-/tmp/CollegeToolbarRecordDD}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

rm -rf "$SNAPSHOT_DIR"
mkdir -p "$SNAPSHOT_DIR"

cd "$ROOT"
"$SCRIPT_DIR/college-xcodebuild-test.sh" \
  -scheme College \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  test \
  -only-testing:CollegeTests/ToolbarVisualTests

echo "Snapshots written to $SNAPSHOT_DIR"
