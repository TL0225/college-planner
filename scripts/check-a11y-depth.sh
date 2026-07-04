#!/usr/bin/env bash
# Part 10 — accessibility depth gate (landmarks, Dynamic Type, sheets).
set -euo pipefail
cd "$(dirname "$0")/.."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$SCRIPT_DIR/college-xcodebuild-test.sh" -project College.xcodeproj -scheme College -configuration Debug \
  -destination 'platform=macOS' \
  -only-testing:CollegeTests/AccessibilityDepthTests \
  -only-testing:CollegeTests/GlassToolbarAccessibilityTests \
  CODE_SIGNING_ALLOWED=NO \
  test >/dev/null
echo "ok: a11y depth PASS"
