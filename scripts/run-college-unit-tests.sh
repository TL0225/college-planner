#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

CLASSES=(
  DegreeTypeInferenceTests CatalogWAFDetectionTests ProgramCatalogParserTests
  CalendarCacheEnginePerfTests LocalLLMRunnerMemoryTests AIAssistantPhase8ToolsTests
  AssistantSecurityTests AssistantSettingsKeyTests AssistantPlanJSONParserTests
  AssistantProfessionalHandbookRegistryTests AssistantIntentNLModelRoutingTests
  AssistantIntentEmbeddingTests AssistantInferenceAvailabilityTests AssistantInferenceSessionTests
  FMRegistryToolAdapterTests AppUpdateCheckServiceTests UserDefaultsWindowAutosaveCleanupTests
  PlannerChunkProjectionCalendarTests PlannerVectorStoreTests
  DSUProgramRequirementsParserTests CatalogProgramRequirementsHydratorTests
  CatalogPolicyIngestionTests CatalogVectorStoreScopeTests CatalogVectorIngestionTests
  LaunchPerformanceAcceptanceTests
)

FAILED=()
PASSED=0

for c in "${CLASSES[@]}"; do
  echo "=== $c ==="
  OUT=$(xcodebuild -scheme College -destination 'platform=macOS' \
    -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
    test-without-building -only-testing:"CollegeTests/$c" 2>&1) || true
  if ! echo "$OUT" | grep -qE "TEST (SUCCEEDED|EXECUTE SUCCEEDED)"; then
    echo "FAIL $c (xcodebuild)"
    FAILED+=("$c")
    echo "$OUT" | grep -E "error:|TEST FAILED" | head -5
    continue
  fi
  if echo "$OUT" | grep -q "failed on"; then
    echo "FAIL $c (assertions)"
    FAILED+=("$c")
    echo "$OUT" | grep "failed on"
    continue
  fi
  PASSED=$((PASSED + 1))
  echo "OK $c"
done

echo ""
echo "PASSED: $PASSED / ${#CLASSES[@]}"
if ((${#FAILED[@]} > 0)); then
  echo "FAILED: ${FAILED[*]}"
  exit 1
fi
