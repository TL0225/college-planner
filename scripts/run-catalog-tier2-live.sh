#!/usr/bin/env bash
# Tier 2 live catalog verification (full scraper-backed E2E; requires network + WebView).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# App-hosted unit tests read env from the test host process; launchctl propagates to GUI/test runners.
launchctl setenv COLLEGE_RUN_LIVE_TESTS 1
export COLLEGE_RUN_LIVE_TESTS=1
trap 'launchctl unsetenv COLLEGE_RUN_LIVE_TESTS 2>/dev/null || true' EXIT

bash scripts/college-xcodebuild-test.sh -project College.xcodeproj -scheme College -destination 'platform=macOS' \
  -only-testing:"CollegeTests/CatalogVerificationLiveSuiteTests/testModernCampusScraperBackedSchoolsScrapeEndToEnd" \
  -only-testing:"CollegeTests/CatalogVerificationLiveSuiteTests/testCourseLeafScraperBackedSchoolsScrapeEndToEnd" \
  -only-testing:"CollegeTests/CatalogVerificationLiveSuiteTests/testCoursedogScraperBackedSchoolsScrapeEndToEnd" \
  test "$@"
