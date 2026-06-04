# Swift Audit Implementation Roadmap

Date: 2026-04-27  
Build surface checked: `College.xcodeproj`  
Scheme: `College`  
Targets: `College`, `CollegeTests`, `CollegeUITests`  
Current toolchain: Apple Swift **6.3.1**, Xcode **26.4.1**  
Current project Swift setting: **6.0**

This roadmap implements the findings from `SWIFT_FULL_AUDIT_REPORT.md` and the master plan at `/Users/timothy/.cursor/plans/swift_legacy_audit_plan_cc984126.plan.md`.

## Implementation Principles

- Do the work in small, reviewable waves.
- Measure before optimizing.
- Delete only after reference verification.
- Move to Swift 6.3 before large refactors so compiler diagnostics guide modernization.
- Keep compatibility removals behind proof: usage checks, tests, or migration evidence.

## Validation Commands

Use these as the default gates for each implementation wave:

```bash
xcodebuild -project College.xcodeproj -scheme College -configuration Debug build
xcodebuild -project College.xcodeproj -scheme College -configuration Release build
xcodebuild test -project College.xcodeproj -scheme College -destination 'platform=macOS'
```

If UI tests are too slow/flaky for every wave, run them on deletion/migration/performance waves and keep unit tests as the default PR gate.

## Wave 0: Baseline and Safety Net

Goal: capture current behavior before changing code.

Actions:
- Record clean Debug and Release build status.
- Record unit/UI test pass/fail baseline.
- Record launch and interaction timing for:
  - app startup,
  - catalog search,
  - calendar sync,
  - assistant streaming,
  - vault document preview,
  - stale file scanning.
- Save current dependency state, especially `mlx-swift-lm` pinned to `main`.

Exit criteria:
- Known baseline failures are documented.
- Any later regression can be compared against this baseline.

## Wave 1: Swift 6.3 Migration

Goal: move project language mode from Swift 6.0 to Swift 6.3 before structural refactors.

Actions:
- Update all `SWIFT_VERSION = 6.0;` entries in `College.xcodeproj/project.pbxproj` to Swift 6.3.
- Build the `College` scheme.
- Fix compiler errors in this order:
  1. app target,
  2. unit test target,
  3. UI test target,
  4. dependency integration surfaces.
- Treat new concurrency diagnostics seriously; avoid broad `@unchecked Sendable` or `nonisolated(unsafe)` unless there is no better local fix.

Validation:
- Debug build passes.
- Release build passes.
- Unit tests pass or failures are documented as pre-existing.

Rollback criteria:
- critical dependency cannot compile under Swift 6.3,
- runtime crash appears in startup/Core Data/calendar/assistant smoke paths,
- migration requires broad unrelated refactors.

## Wave 2: Delete-Safe Cleanup

Goal: reduce obvious dead code before refactoring large systems.

Tier 1 candidates to verify then remove:
- `College/CalendarTopPill.swift`
- `College/CalendarBottomPill.swift`
- `College/SelectionInspectorPill.swift`
- `College/App/TahoeGlassPane.swift`
- `College/WhatIfView.swift`
- `College/Settings/ResourcesView.swift`
- `College/Catalog/UniversitySearchView.swift`
- `College/ConfigureBachelorsView.swift`
- `College/ConfigureMastersView.swift`
- `College/ConfigurePhdView.swift`

Tier 2 candidates needing extra review:
- `College/Services/CatalogBackgroundSyncRunner.swift`
- `College/Intelligence/IntelligenceDebugView.swift`
- `College/Intelligence/ToolCallStreamParser.swift` (`ToolCallStreamParseResult`)

Verification before removal:
- no Swift references,
- no Xcode project/manual target dependency issue,
- no dynamic menu/route/test-only use,
- build/test pass after deletion.

## Wave 3: High-Impact Performance Fixes

Goal: remove likely UI hitches and obvious bottlenecks before deeper architecture work.

Priority order:
1. Move `College/Services/StaleFileMonitor.swift` scanning off the main actor.
2. Remove N+1 fetch patterns in `College/CoreData/CoreDataManager.swift` requirement/import paths.
3. Keep catalog search in `College/Courses/CourseSearchView.swift` read-only and off heavy write/backfill paths.
4. Move vault read/decrypt/write work in `CoreDataManager` off main-actor execution.
5. Coalesce calendar cache rebuild triggers in `College/Calendar/CalendarView.swift`.
6. Reduce repeated startup work in `College/App/LaunchUpdateCheckService.swift`.
7. Split high-churn assistant UI subtrees in `College/Intelligence/AIAssistantView.swift`.

Validation:
- compare timing against Wave 0 baseline,
- check UI hitch traces where relevant,
- run build/tests after each isolated change.

## Wave 4: Legacy Compatibility Sunset

Goal: remove compatibility paths only when removal is provably safe.

Targets:
- `College/CoreData/PersistenceController.swift` legacy store migration path.
- `College/CoreData/AppBackupManager.swift` legacy plaintext backup support.
- `College/App/OnboardingRootView.swift` legacy catoid fallback.
- `College/Catalog/CatalogModels.swift` legacy requirement fields.
- `College/Catalog/ModernCampusAPI.swift` compatibility shim.
- `College/App/LMSPortalConfiguration.swift` legacy UserDefaults key.

Process:
- add or identify tests proving current-format behavior,
- document migration/removal criteria,
- remove one compatibility path per PR/wave,
- keep backup/restore and onboarding smoke checks in the validation gate.

## Wave 5: Core Architecture Refactors

Goal: reduce the blast radius in oversized files after tests and performance quick wins are in place.

Refactor order:
1. Extract low-risk helpers from `CoreDataManager` without changing behavior.
2. Extract requirement import/query services from `CoreDataManager`.
3. Extract sync/provider responsibilities from `CalendarIntegrationManager`.
4. Split large SwiftUI views into stable subviews:
   - `AIAssistantView.swift`,
   - `CalendarView.swift`,
   - `DocumentsView.swift`,
   - `ContentView.swift`.

Rule:
- preserve public call sites behind facades until tests prove behavior parity.

## Wave 6: Test Stability and Coverage

Goal: make the test suite reliable enough to support the refactors.

Actions:
- Replace fixed sleeps in UI tests with predicate-based waits.
- Move heavy/performance UI tests to a separate lane if they slow normal validation.
- Add behavior tests for assistant persistence/state transitions.
- Add Core Data tests for migration/bootstrap/failure cases.
- Remove template/stale tests if verified unused:
  - `CollegeTests/CollegeTests.swift`,
  - `CollegeUITests/CollegeUITests.swift`,
  - `CollegeUITests/CollegeUITestsLaunchTests.swift`.

## Wave 7: Dependency Hygiene

Goal: reduce surprise regressions from dependencies.

Actions:
- Replace `mlx-swift-lm` branch pin with a stable revision/tag policy.
- Add dependency upgrade checklist:
  - build,
  - model load smoke,
  - assistant/local LLM smoke,
  - startup/memory check.
- Monitor MLX-family deprecations; only change app code where app imports deprecated APIs.

## Recommended First Implementation Sequence

1. Run Wave 0 baseline.
2. Perform Swift 6.3 migration.
3. Verify and remove Tier 1 deletion candidates.
4. Fix `StaleFileMonitor` main-thread scan.
5. Fix the highest-impact `CoreDataManager` fetch bottleneck.
6. Stabilize UI waits in the most flaky/slow UI tests.
7. Begin `CoreDataManager` extraction behind a facade.

