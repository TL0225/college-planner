#!/usr/bin/env bash
# Master plan completion gate — runs all Part 30 + excellence CI scripts.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts=(
  check-wave1-regression.sh
  check-spatial-surfaces.sh
  check-motion-tokens.sh
  check-shell-performance-gates.sh
  check-toolbar-menu-parity.sh
  check-share-extension-entitlements.sh
  check-a11y-depth.sh
  check-ftue-empty-states.sh
)

for script in "${scripts[@]}"; do
  echo "== $script =="
  bash "scripts/$script"
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$SCRIPT_DIR/college-xcodebuild-test.sh" -project College.xcodeproj -scheme College -configuration Debug \
  -destination 'platform=macOS' \
  -only-testing:CollegeTests/ShellP95BudgetContractTests \
  -only-testing:CollegeTests/PerformanceBaselineAcceptanceTests \
  CODE_SIGNING_ALLOWED=NO \
  test >/dev/null

bash scripts/generate-hig-completion-gate.sh
overall=$(python3 -c "import json; print(json.load(open('build/hig-completion-gate.json'))['overall'])")
if [[ "$overall" != "100" ]]; then
  echo "error: completion gate $overall/100"
  exit 1
fi
echo "ok: master plan completion gate PASS ($overall/100)"
