#!/usr/bin/env bash
# Delete and re-seed ToolbarVisual snapshot baselines.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SNAPSHOT_DIR="$ROOT/CollegeTests/__Snapshots__/ToolbarVisual"
DERIVED="${DERIVED:-/tmp/CollegeToolbarRecordDD}"

rm -rf "$SNAPSHOT_DIR"
mkdir -p "$SNAPSHOT_DIR"

cd "$ROOT"
xcodebuild \
  -scheme College \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO \
  test \
  -only-testing:CollegeTests/ToolbarVisualTests

echo "Snapshots written to $SNAPSHOT_DIR"
