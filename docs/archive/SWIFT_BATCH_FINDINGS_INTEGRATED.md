# Swift Batch Findings Integrated Addendum

Date: 2026-04-27

This addendum integrates the completed batch audit reports into the main audit package. It preserves the distinction between app-owned remediation work and dependency-watch findings from `SourcePackages/checkouts`.

## Coverage Status

- All 11 batches completed.
- Total Swift files reviewed: **1283 / 1283**.
- App-owned and test files produced concrete remediation candidates.
- Dependency batches mostly produced package-level watch items, not in-tree deletion/refactor targets.

## App-Owned Findings To Carry Forward

### Batch 01

- `College/Academics/AcademicsAuditPanel.swift`
  - Empty/stub file; strong delete candidate after project/reference verification.
- `College/CoreData/PersistenceController.swift`
  - High user-data risk: persistent-store load failure uses fatal termination.
- `College/CoreData/CoreDataManager.swift`
  - Highest-risk god object; persistence, feature logic, import, diagnostics, and possible main-thread blocking.
- `College/CoreData/AppBackupManager.swift`
  - Backup format and migration sensitivity; test-first before compatibility changes.
- `College/App/CollegeApp.swift`
  - Startup/global-state concentration.
- `College/App/AppCompatibility.swift`
  - URL dispatcher currently returns success but generic `.onOpenURL` path is effectively no-op.
- `College/Calendar/CalendarCourseLinker.swift`
  - Data-altering automation from calendar titles; test-first risk.
- `College/Brightspace/BrightspaceKeychainService.swift`
  - Documentation says internet password, implementation uses generic password.
- `College/Catalog/SchoolScrapers/*.swift`
  - Placeholder scraper files are delete candidates after build/reference verification.
- Mega-file cluster remains high priority:
  - `College/Calendar/CalendarIntegrationManager.swift`
  - `College/Calendar/CalendarView.swift`
  - `College/Catalog/ModernCampusEngine.swift`
  - `College/Catalog/UniversalCatalogScraper.swift`
  - `College/App/ContentView.swift`
  - `College/App/OnboardingRootView.swift`
  - `College/Intelligence/AIAssistantView.swift`

### Batch 02

- `College/Services/CatalogBackgroundSyncRunner.swift`
  - Critical: Phase B catalog import work runs through `@MainActor`; heavy network/parsing/import work should move off the UI actor if retained.
- `College/Intelligence/IntelligenceService.swift`
  - `nonisolated(unsafe)` cache and force regex construction require concurrency discipline.
- `College/MajorDetailsView.swift` and `College/MajorMinorDetailsView.swift`
  - Large duplicated SwiftUI flows; extract shared pipeline.
- `College/Overview/OverviewView.swift`, `College/Profile/AcademicIdentityView.swift`, `College/SyllabusAI/SyllabusReviewView.swift`, `College/Settings/ResourcesView.swift`
  - Large SwiftUI recomposition surfaces.
- `College/Services/CloudIntegrationService.swift`
  - Main-actor singleton init starts provider scans and loops.
- `College/Intelligence/AssistantWebPageExtractor.swift`
  - WebKit fetch path intentionally main-actor-bound; must be timeout-bound and profiled.
- `College/Rust/CollegeCoreSwift.swift`
  - FFI assumes non-null C results when Rust path is linked.
- `CollegeTests/ModernCampusParsingUBTests.swift`
  - Large fixture-heavy test file; split by parser concern.

### Batch 03

- `CollegeTests/StonyBrookParsingTests.swift`
  - Entire class skipped; catalog parser regression coverage is effectively disabled.
- `CollegeTests/OrgUnitNormalizationTests.swift`
  - Local normalization copy can drift from production behavior.
- `CollegeTests/SearXNGClientTests.swift`
  - Static `URLProtocol` handler and process-wide settings are fragile under parallel tests.
- `CollegeUITests/UITestCollegeHarness.swift`
  - Long-wait mode can create extreme waits if enabled accidentally.
- `CollegeUITests/AppWidePerformanceUITests.swift`
  - Heavy performance flow lacks the same UI-test gating as some other files.
- `CollegeUITests/AssistantComprehensiveAnalysisUITests.swift`
  - Non-deterministic LLM rubric and repo-adjacent report writes.
- `CollegeUITests/CollegeUITests.swift` and `CollegeUITests/CollegeUITestsLaunchTests.swift`
  - Use ambiguous `XCUIApplication()` rather than explicit bundle ID.

## Dependency Findings To Carry Forward

### MLX / MLX-LM

- `mlx-swift-lm` and related packages remain dependency-watch, not direct edit targets.
- Highest risks:
  - `mlx-swift-lm` branch pinning / floating ranges,
  - fatal-error-heavy model/cache/config paths,
  - KV cache and evaluation hot paths,
  - MLX C error handling defaulting to process termination without scoped error handling,
  - large generated/integration tests affecting CI/tooling.
- App action:
  - pin dependency intentionally,
  - wrap app-visible MLX work with safe error handling,
  - validate model IDs/configs before loading,
  - keep model load/prewarm off user-visible paths.

### swift-collections / swift-atomics / swift-numerics

- Mostly dependency-watch.
- Do not delete individual checkout files.
- Highest risks:
  - unsafe internals and precondition/fatal traps expected in collection implementations,
  - `@unchecked Sendable` container/index conformances require call-site discipline,
  - autogenerated tests and benchmark/test-support sources create indexing/CI noise,
  - build flags such as `COLLECTIONS_INTERNAL_CHECKS` should not be enabled accidentally in production.

### swift-transformers / swift-jinja

- Mostly dependency-watch.
- Highest risks:
  - Hub/network/token download surface,
  - tokenizer/model code using `fatalError` / `try!` for malformed configs,
  - Jinja `Environment` is `@unchecked Sendable` with mutable state,
  - live-network Hub tests can be flaky if included in app CI.
- App action:
  - do not use arbitrary remote model/tokenizer configs without validation,
  - avoid sharing Jinja environments across concurrency domains unless disciplined,
  - keep Hub/download work off UI paths and ensure token handling is private.

## Updated Remediation Priority

1. Keep Swift 6.3 migration, because Debug build passes.
2. Fix or document test-runner bootstrap timeout before trusting full test validation.
3. Verify and remove app-owned stub/dead files only after reference/project checks.
4. Address critical main-actor bottlenecks:
   - `StaleFileMonitor`
   - `CatalogBackgroundSyncRunner` if retained
   - `CoreDataManager` hot fetch/import paths
5. Stabilize tests:
   - unskip Stony Brook parser tests or replace them,
   - align UI test gating and bundle identifiers,
   - isolate heavy/perf/LLM UI suites.
6. Treat dependency findings through package policy, pinning, and app call-site validation.

