# Swift Remediation Sequence

Date: 2026-04-27

This sequence turns the audit findings into implementation waves. It is dependency-aware: compiler migration and safety nets happen before broad refactors, deletions happen before architectural extraction, and performance fixes target the most user-visible bottlenecks first.

## Wave 0: Baseline

- Artifact: `SWIFT_63_MIGRATION_BASELINE.md`
- Status:
  - Debug build passed.
  - Release signing failed due missing development team.
  - Unsigned Release build stalled in dependency build phase and was stopped.
- Gate before proceeding:
  - Debug build must remain green.
  - Release signing issue should not block Swift migration, but should be tracked separately.

## Wave 1: Swift 6.3 Migration

Why first:
- The local toolchain is already Swift 6.3.1.
- Compiler diagnostics should guide modernization before large refactors.

Steps:
1. Update `SWIFT_VERSION` from `6.0` to `6.3`.
2. Run Debug build.
3. Fix app target compiler issues.
4. Fix tests.
5. Run tests or document baseline failures.

Gate:
- `xcodebuild -project College.xcodeproj -scheme College -configuration Debug build`
- `xcodebuild test -project College.xcodeproj -scheme College -destination 'platform=macOS'`

## Wave 2: Delete-Safe Cleanup

Why second:
- Reduces code surface before refactors and lowers future build/test load.

Tier 1:
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

Tier 2:
- `College/Services/CatalogBackgroundSyncRunner.swift`
- `College/Intelligence/IntelligenceDebugView.swift`
- `College/Intelligence/ToolCallStreamParser.swift`

Gate:
- reference check,
- Debug build,
- targeted UI smoke if a view file was removed.

## Wave 3: Critical Performance Fixes

Order:
1. `College/Services/StaleFileMonitor.swift`: move scans off main actor.
2. `College/CoreData/CoreDataManager.swift`: remove N+1 requirement/import fetches.
3. `College/CoreData/CoreDataManager.swift`: move vault decrypt IO off main actor.
4. `College/Courses/CourseSearchView.swift`: remove heavy write/backfill from interactive search.
5. `College/Calendar/CalendarView.swift`: coalesce cache rebuild triggers.

Gate:
- Debug build,
- targeted smoke,
- compare against baseline interaction timings where possible.

## Wave 4: Test Stabilization

Why here:
- Needed before large architecture changes.

Steps:
- Replace fixed sleeps in UI tests with predicate waits.
- Add assistant state/persistence coverage.
- Add Core Data migration/bootstrap/failure coverage.
- Remove template tests if verified unused.

Gate:
- test suite has fewer fixed sleeps,
- key high-risk modules have regression coverage.

## Wave 5: Legacy Compatibility Sunset

Targets:
- `PersistenceController` legacy store migration.
- `AppBackupManager` legacy plaintext backup.
- `OnboardingRootView` legacy catoid fallback.
- `CatalogModels` legacy requirement fields.
- `ModernCampusAPI` compatibility shim.
- `LMSPortalConfiguration` legacy key.

Rule:
- One compatibility path per change wave.
- Each removal must include proof: test, telemetry/log evidence, or migration criteria.

## Wave 6: Architecture Extraction

Order:
1. Extract low-risk helpers from `CoreDataManager`.
2. Extract requirement import/query logic.
3. Extract calendar provider sync/auth logic.
4. Split large SwiftUI views into stable subviews.

Gate:
- public behavior preserved through facades,
- tests/smokes pass after each extraction.

## Wave 7: Dependency Hygiene

Steps:
- Pin `mlx-swift-lm` away from `main`.
- Establish scheduled dependency upgrade process.
- Monitor MLX deprecations without vendored edits unless app-blocking.

Gate:
- build passes,
- local LLM/model load smoke passes,
- startup/memory smoke does not regress.

