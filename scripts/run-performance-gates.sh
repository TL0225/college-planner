#!/usr/bin/env bash
# Phase 6 automated performance / migration gates (macOS).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

CONFIG="${1:-Debug}"
DEST='platform=macOS'

echo "== Deletion guards =="
./scripts/check-neutral-persistence-labels.sh
./scripts/check-no-vision-llm.sh
./scripts/check-no-gemma4.sh

echo "== XCTest ($CONFIG) =="
if [[ "$CONFIG" == "Release" ]]; then
  "$SCRIPT_DIR/college-xcodebuild-test.sh" -scheme College -destination "$DEST" -configuration Release -jobs 1 \
    -only-testing:CollegeTests/LaunchPerformanceAcceptanceTests \
    -only-testing:CollegeTests/PerformanceBaselineAcceptanceTests \
    -only-testing:CollegeTests/CollegeCoreSwiftRegressionTests \
    -only-testing:CollegeTests/Persistence/SchemaMigrationPlanTests \
    -only-testing:CollegeTests/Persistence/LaunchSingleCatalogMmapTests \
    test
else
  "$SCRIPT_DIR/college-xcodebuild-test.sh" -scheme College -destination "$DEST" -configuration Debug -jobs 1 \
    -only-testing:CollegeTests \
    test
fi

echo "ok: performance gates ($CONFIG)"
