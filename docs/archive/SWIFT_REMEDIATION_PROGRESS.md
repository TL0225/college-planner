# Swift Remediation Progress

Date: 2026-04-27

## Completed

### Swift 6.3 Migration

- Updated project Swift language setting to `SWIFT_VERSION = 6.3`.
- Debug build passes with Swift 6.3.
- Full test run remains blocked by test-runner bootstrap timeouts before tests execute.

### Batch Audit Integration

- Integrated completed batch findings in `SWIFT_BATCH_FINDINGS_INTEGRATED.md`.
- Confirmed batch coverage in `SWIFT_BATCH_AUDIT_COMPLETION.md`.

### Dead-Code Cleanup

Deleted verified no-reference/stub candidates:

- `College/Academics/AcademicsAuditPanel.swift`
- `College/Catalog/SchoolScrapers/ModernCampusSchoolScrapers.swift`
- `College/Catalog/SchoolScrapers/SchoolScraper.swift`
- `College/Catalog/SchoolScrapers/StonyBrookUniversityScraper.swift`
- `College/Catalog/SchoolScrapers/UniversityAtBuffaloScraper.swift`
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

Validation:

- Debug build passed after deletion.

### Critical Bottleneck Fix: `StaleFileMonitor`

Changed `College/Services/StaleFileMonitor.swift` so stale-file scans:

- snapshot main-actor state,
- run filesystem enumeration in a detached utility task,
- stream the enumerator instead of materializing `enumerator.allObjects`,
- publish only the final stale count back to the main actor.

Validation:

- `ReadLints` reported no diagnostics for `StaleFileMonitor.swift`.
- Debug build passed after the change.

### Bottleneck Reduction: `CatalogBackgroundSyncRunner`

Changed `College/Services/CatalogBackgroundSyncRunner.swift` so Phase B background course import keeps app coordination on the main actor but moves the expensive per-catalog `ModernCampusEngine.fetchAllCourses` work into a detached utility task with only Sendable string inputs.

This avoids sending non-Sendable app services (`CoreDataManager`, `AppNotificationCenter`) across detached task boundaries while still moving the course fetch/scrape work off the main actor.

Validation:

- Initial fully-detached approach was rejected by Swift 6 sendability checks.
- Narrowed implementation is lint-clean.
- Debug build passed after the change.

### UI Test Launch Stabilization

Changed template UI tests to use `UITestCollegeHarness.makeCollegeApp()` and `UITestCollegeHarness.launchWithRetry(_:)` instead of ambiguous `XCUIApplication()` and duplicated retry loops.

Files:

- `CollegeUITests/CollegeUITests.swift`
- `CollegeUITests/CollegeUITestsLaunchTests.swift`

Validation:

- `ReadLints` reported no diagnostics for both files.
- Debug build passed after the change.

## Remaining Blockers

- Full `xcodebuild test` is still blocked by test-runner bootstrap timeouts/early exits, not by Swift compilation.
- Release build remains blocked by signing unless `CODE_SIGNING_ALLOWED=NO`; unsigned Release previously stalled in dependency compilation.

