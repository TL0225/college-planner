#!/usr/bin/env bash
# Run offline catalog unit tests (no live network).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="${DERIVED:-/tmp/CollegeCatalogTestsDD}"
DEST="${DEST:-platform=macOS}"

FILTER="${1:-}"

ARGS=(
  -scheme College
  -destination "$DEST"
  -derivedDataPath "$DERIVED"
  test
)

if [[ -n "$FILTER" ]]; then
  ARGS+=(-only-testing:"CollegeTests/$FILTER")
else
  ARGS+=(
    -only-testing:CollegeTests/CatalogIngestGateTests
    -only-testing:CollegeTests/CatalogGraphDiscoveryTests
    -only-testing:CollegeTests/CourseLeafSitemapCacheTests
    -only-testing:CollegeTests/CourseLeafLayoutClassifierTests
    -only-testing:CollegeTests/CatalogEntityIdentityTests
    -only-testing:CollegeTests/CatalogDocumentIRGoldenTests
    -only-testing:CollegeTests/CatalogInvariantSanityFixtureTests
    -only-testing:CollegeTests/CatalogIngestGateModernCampusTests
    -only-testing:CollegeTests/ModernCampusCatalogDiscovererTests
    -only-testing:CollegeTests/CourseLeafGoldenFixtureTests
    -only-testing:CollegeTests/CatalogLayoutDriftTests
    -only-testing:CollegeTests/CatalogStructuralDiffEngineTests
    -only-testing:CollegeTests/CatalogLayoutLLMClassifierTests
    -only-testing:CollegeTests/CatalogPDFToDocumentIRAdapterTests
    -only-testing:CollegeTests/CatalogDocumentIRStoreTests
    -only-testing:CollegeTests/ModernCampusIRCourseExtractorTests
    -only-testing:CollegeTests/ModernCampusCatalogIngestAdapterTests
    -only-testing:CollegeTests/CatalogExternalReferenceBuilderTests
    -only-testing:CollegeTests/CatalogEntityLLMValidatorTests
    -only-testing:CollegeTests/CatalogLayoutProfileGovernanceTests
    -only-testing:CollegeTests/UniversalCatalogScraperIRConsumerTests
    -only-testing:CollegeTests/CatalogManifestCapabilitiesTests
  )
fi

cd "$ROOT"
xcodebuild "${ARGS[@]}"
