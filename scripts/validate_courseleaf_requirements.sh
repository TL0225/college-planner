#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

SCHOOL="${1:-new_york_university}"
SCHEME="${SCHEME:-College}"
DEST="${DESTINATION:-platform=macOS}"

echo "Running CourseLeaf requirements school-wide tests (fixtures + optional live) for: $SCHOOL"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$SCRIPT_DIR/college-xcodebuild-test.sh" -scheme "$SCHEME" -destination "$DEST" test \
  -only-testing:"CollegeTests/CourseLeafRequirementsGoldenTests" \
  -only-testing:"CollegeTests/CourseLeafRequirementsSectionTests" \
  -only-testing:"CollegeTests/CourseLeafCourselistParserSemanticsTests" \
  -only-testing:"CollegeTests/CourseLeafRequirementsXMLTests" \
  -only-testing:"CollegeTests/CourseLeafRequirementsBreakdownGoldenTests" \
  -only-testing:"CollegeTests/CourseLeafRequirementsSchoolWideTests" \
  -only-testing:"CollegeTests/CourseLeafNYUCSBABreakdownRegressionTests" \
  -only-testing:"CollegeTests/NYUCourseLeafRequirementsParserTests/testParseNYUCASComputerScienceBA_fixture" \
  -only-testing:"CollegeTests/RequirementProgressEngineTests" \
  -only-testing:"CollegeTests/RequirementFulfillmentStoreTests" \
  -only-testing:"CollegeTests/DSUProgramRequirementsParserTests" \
  2>&1 | tee "build/courseleaf-requirements-test-${SCHOOL}.log"

echo "Done. Log: build/courseleaf-requirements-test-${SCHOOL}.log"
