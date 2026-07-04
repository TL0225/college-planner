#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/xcodebuild-test-parallel-flags.sh
source "$SCRIPT_DIR/xcodebuild-test-parallel-flags.sh"

DERIVED="${DERIVED:-/tmp/CollegeUnitTestsDD}"
DEST="${DEST:-platform=macOS}"

echo "=== Packages/CollegeCalendar (CalendarCacheEngineTests) ==="
(cd Packages/CollegeCalendar && swift test --filter CalendarCacheEngineTests)

# Fresh CI runners have no prior build products; compile once, then shard with
# test-without-building against the same DerivedData.
echo "=== build-for-testing (College) ==="
bash "$SCRIPT_DIR/college-xcodebuild-test.sh" \
  -scheme College \
  -destination "$DEST" \
  -derivedDataPath "$DERIVED" \
  build-for-testing

CLASSES=(
  DegreeTypeInferenceTests CatalogWAFDetectionTests ProgramCatalogParserTests
  LocalLLMRunnerMemoryTests AIAssistantPhase8ToolsTests
  AssistantSecurityTests AssistantSettingsKeyTests AssistantPlanJSONParserTests
  AssistantProfessionalHandbookRegistryTests AssistantIntentNLModelRoutingTests
  AssistantIntentEmbeddingTests AssistantInferenceAvailabilityTests AssistantInferenceSessionTests
  FMRegistryToolAdapterTests AppUpdateCheckServiceTests UserDefaultsWindowAutosaveCleanupTests
  PlannerChunkProjectionCalendarTests PlannerVectorStoreTests
  DSUProgramRequirementsParserTests CatalogProgramRequirementsHydratorTests
  CatalogPolicyIngestionTests CatalogVectorStoreScopeTests CatalogVectorIngestionTests
  LaunchPerformanceAcceptanceTests
  AppDataStoreLaunchSafetyTests VaultHierarchyIntegrityTests DataWipeCompletenessTests
  ShareExtensionEntitlementsTests ProductAnalyticsTests OfflineCoreFlowsIntegrationTests
  MotionAccessibilityTests CalendarSmartListTests AccessibilityDepthTests
  EmptyStateContractTests FTUEPathContractTests ShellP95BudgetContractTests
  CollegePersistenceSavePathTests CatalogPDFExtractorSafetyTests CrashSignalHandlerAuditTests
  MenuBarStatusPayloadTests CollegeSchemaLegacyStoreRepairTests ScoreboardGeneratorTests
  JobBoardRelationshipIntegrityTests DiagnosticsPlatformTests
  PlannerCoursePersistenceFlowTests LMSKeychainRoundTripTests CalendarEventCRUDFlowTests
  LaunchDashboardFlowTests CatalogNavigationFlowTests VaultFilesystemConsistencyFlowTests
)

FAILED=()
PASSED=0

for c in "${CLASSES[@]}"; do
  echo "=== $c ==="
  OUT=$(bash "$SCRIPT_DIR/college-xcodebuild-test.sh" \
    -scheme College \
    -destination "$DEST" \
    -derivedDataPath "$DERIVED" \
    test-without-building -only-testing:"CollegeTests/$c" 2>&1) || true
  if ! echo "$OUT" | grep -qE "TEST (SUCCEEDED|EXECUTE SUCCEEDED)"; then
    echo "FAIL $c (xcodebuild)"
    FAILED+=("$c")
    # pipefail: grep exit 1 when no matches must not abort the shard loop
    echo "$OUT" | grep -E "error:|TEST (EXECUTE )?FAILED|Could not launch|failed on|Failing tests|Issue recorded|✘" | head -20 || true
    echo "$OUT" | tail -20
    continue
  fi
  if echo "$OUT" | grep -q "failed on"; then
    echo "FAIL $c (assertions)"
    FAILED+=("$c")
    echo "$OUT" | grep "failed on" || true
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
