#!/usr/bin/env bash
# Run CollegeTests in sequential shards to avoid SQLite/MLX/singleton contention.
set -euo pipefail
cd "$(dirname "$0")/.."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

SHARDS=(
  "BackgroundServiceComplianceTests BackgroundServiceAntiPatternTests BackgroundServiceRegistryTests"
  "AppBackupRestoreStoreTests AppDataStoreLaunchSafetyTests CollegePersistenceSavePathTests"
  "CalendarEventCRUDFlowTests CalendarSyncIngestIntegrationTests CalendarSmartListTests"
  "CatalogIngestParityDiffTests CatalogDocumentIRGoldenTests CatalogPDFExtractorSafetyTests"
  "ToolbarArchitectureTests ToolbarVisualTests"
  "DakotaStateUniversityCatalogScraperTests CatalogNavigationFlowTests"
  "LaunchPerformanceAcceptanceTests OfflineCoreFlowsIntegrationTests"
  "VaultHierarchyIntegrityTests VaultFilesystemConsistencyFlowTests DataWipeCompletenessTests"
  "AssistantSecurityTests AIAssistantPhase8ToolsTests LocalLLMRunnerMemoryTests"
  "JobBoardRelationshipIntegrityTests PlannerVectorStoreTests"
)

FAILED=()
PASSED=0

for shard in "${SHARDS[@]}"; do
  echo "=== Shard: $shard ==="
  ONLY_ARGS=()
  for suite in $shard; do
    ONLY_ARGS+=("-only-testing:CollegeTests/$suite")
  done

  if ! bash "$SCRIPT_DIR/college-xcodebuild-test.sh" \
    -scheme College \
    -destination 'platform=macOS' \
    test "${ONLY_ARGS[@]}"; then
    echo "FAIL shard: $shard"
    FAILED+=("$shard")
    continue
  fi
  PASSED=$((PASSED + 1))
  echo "OK shard: $shard"
done

echo ""
echo "PASSED: $PASSED / ${#SHARDS[@]}"
if ((${#FAILED[@]} > 0)); then
  echo "FAILED shards:"
  printf '  - %s\n' "${FAILED[@]}"
  exit 1
fi
