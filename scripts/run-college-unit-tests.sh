#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/xcodebuild-test-parallel-flags.sh
source "$SCRIPT_DIR/xcodebuild-test-parallel-flags.sh"

echo "=== Packages/CollegeCalendar (CalendarCacheEngineTests) ==="
(cd Packages/CollegeCalendar && swift test --filter CalendarCacheEngineTests)

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
  OUT=$(xcodebuild -scheme College -destination 'platform=macOS' \
    "${XCODEBUILD_TEST_PARALLEL_ARGS[@]}" \
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
