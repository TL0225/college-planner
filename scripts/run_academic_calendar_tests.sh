#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

DESTINATION="${ACADEMIC_CALENDAR_TEST_DESTINATION:-platform=macOS}"

"$SCRIPT_DIR/college-xcodebuild-test.sh" \
  -scheme College \
  -destination "$DESTINATION" \
  -only-testing:CollegeTests/AcademicCalendarExtractorTests \
  -only-testing:CollegeTests/AcademicCalendarSchoolFixtureTests \
  -only-testing:CollegeTests/AcademicCalendarAutoDetectModuleTests \
  -skip-testing:CollegeTests/AcademicCalendarLiveExtractionReportTests \
  CODE_SIGNING_ALLOWED=NO \
  test
