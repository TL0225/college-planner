#!/usr/bin/env bash
# Part 20 — FTUE + empty-state contract gate.
set -euo pipefail
cd "$(dirname "$0")/.."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$SCRIPT_DIR/college-xcodebuild-test.sh" -project College.xcodeproj -scheme College -configuration Debug \
  -destination 'platform=macOS' \
  -only-testing:CollegeTests/FTUEPathContractTests \
  -only-testing:CollegeTests/EmptyStateContractTests \
  CODE_SIGNING_ALLOWED=NO \
  test >/dev/null
echo "ok: FTUE + empty states PASS"
