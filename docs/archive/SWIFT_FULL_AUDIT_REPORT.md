# Swift Full Audit Report

Date: 2026-04-27  
Scope: Full repository Swift audit (read-only, no code edits)

## Coverage Confirmation

- Total Swift files audited: **1283**
- Distribution:
  - `SourcePackages`: **1013**
  - `College`: **229**
  - `CollegeTests`: **31**
  - `CollegeUITests`: **10**

This report reflects findings from a deep pass across app code, tests, and dependencies, with priority on risk, performance impact, and legacy/deletion opportunities.

## Executive Findings

- Highest risk sits in a small set of oversized orchestration/data files where responsibilities are concentrated.
- Multiple legacy compatibility paths are still active and should be intentionally retained or sunset with criteria.
- There are high-probability performance bottlenecks on main-actor work, repeated Core Data fetch patterns, and heavy UI recomposition paths.
- There are likely deletable files/symbols with high confidence, plus medium-confidence candidates requiring one verification step.
- Test suites contain useful coverage but miss some critical state-machine and migration scenarios; UI test stability can be improved.

## High-Priority Legacy Findings

### 1) Responsibility Concentration (High)

- `College/CoreData/CoreDataManager.swift`
  - Very large and multi-purpose (persistence, import behavior, diagnostics, business logic).
  - High regression blast radius and hard-to-isolate behavior changes.
- `College/Calendar/CalendarIntegrationManager.swift`
  - Broad orchestration across provider sync, conflict handling, retries, and persistence coordination.
  - Elevated maintenance and incident risk.

### 2) Active Legacy/Compatibility Paths (High/Medium)

- `College/CoreData/PersistenceController.swift`
  - Legacy store migration path exists (`migrateLegacyStoreIfNeeded`).
- `College/CoreData/AppBackupManager.swift`
  - Legacy plaintext backup compatibility is still supported.
- `College/App/OnboardingRootView.swift`
  - Legacy fallback behavior (`useLegacyCatoidFallback`) present.
- `College/Catalog/CatalogModels.swift`
  - Legacy requirement model fields coexist with newer representations.
- `College/Catalog/ModernCampusAPI.swift`
  - Compatibility shim behavior retained after API rename.
- `College/App/LMSPortalConfiguration.swift`
  - Legacy UserDefaults key fallback still used.

### 3) Transitional/Prototype Surface in Runtime Tree (Medium)

- `College/WhatIfView.swift` appears scaffold-like and possibly unfinished in current runtime tree.
- Overlapping pill components may indicate residual iteration debt:
  - `College/CalendarTopPill.swift`
  - `College/CalendarBottomPill.swift`
  - `College/SelectionInspectorPill.swift`

## Top Bottlenecks and Optimizations

## 1) Main-Thread Filesystem Scanning (Critical)

- File: `College/Services/StaleFileMonitor.swift`
- Issue: large directory scan work runs under `@MainActor`.
- Likely impact: UI hitching for large watched folders.
- Optimization direction:
  - move scan to background actor/queue,
  - stream enumeration instead of materializing all objects,
  - chunk + debounce scan cycles.

## 2) N+1 Core Data Fetch Patterns (Critical/High)

- File: `College/CoreData/CoreDataManager.swift`
- Issue: repeated per-item/per-category fetch loops in import/requirement flows.
- Likely impact: high DB round-trips, slower imports/sync, memory pressure.
- Optimization direction:
  - prefetch to keyed dictionaries,
  - batch updates,
  - reduce repeated fetch+reduce patterns.

## 3) Heavy Search Path Under Interactive UI (High)

- Files:
  - `College/Courses/CourseSearchView.swift`
  - `College/CoreData/CoreDataManager.swift`
- Issue: search can trigger expensive data work and backfill logic.
- Likely impact: typing latency and responsiveness drops.
- Optimization direction:
  - background computation contexts for heavy query/backfill paths,
  - avoid write side-effects in interactive search.

## 4) Synchronous Vault IO/Decrypt on Main-Actor Paths (High)

- File: `College/CoreData/CoreDataManager.swift`
- Issue: sync read/decrypt/write flow in user-facing path.
- Likely impact: interaction stalls for larger files.
- Optimization direction:
  - move IO/decrypt off main actor,
  - publish final URL/state back on main actor.

## 5) Rebuild Churn in Large Calendar UI Flow (Medium-High)

- File: `College/Calendar/CalendarView.swift`
- Issue: many triggers can repeatedly rebuild caches/snapshots.
- Likely impact: extra CPU and frame timing instability.
- Optimization direction:
  - coalesce invalidation triggers,
  - incremental recompute rather than full rebuild.

## 6) Startup/Update Check Efficiency (Medium)

- File: `College/App/LaunchUpdateCheckService.swift`
- Issue: repeated setup work and sync reads in startup path.
- Likely impact: avoidable startup overhead.
- Optimization direction:
  - session/decoder reuse and async/background file work.

## 7) Assistant View Recomposition Pressure (Medium)

- File: `College/Intelligence/AIAssistantView.swift`
- Issue: large view with many state triggers and persistence/scroll reactions.
- Likely impact: diffing/layout churn during streaming updates.
- Optimization direction:
  - split view into smaller stable subviews,
  - coalesce persistence and event handling.

## Likely Unused / Deletable Candidates

These are **candidates**, not auto-delete decisions.

## High-Confidence File Candidates

- `College/CalendarTopPill.swift`
- `College/CalendarBottomPill.swift`
- `College/SelectionInspectorPill.swift`
- `College/App/TahoeGlassPane.swift`
- `College/WhatIfView.swift`
- `College/Services/CatalogBackgroundSyncRunner.swift`
- `College/Settings/ResourcesView.swift`
- `College/Catalog/UniversitySearchView.swift`
- `College/ConfigureBachelorsView.swift`
- `College/ConfigureMastersView.swift`
- `College/ConfigurePhdView.swift`

Rationale: near-zero/no call-site references found in Swift sources during cross-reference pass.

## High-Confidence Symbol Candidates

- `College/Intelligence/AssistantWebMemoryEmbedding.swift` (`data(from:)`)
- `College/Intelligence/AssistantWebSearchRateLimiter.swift` (`resetForTesting`)
- `College/Intelligence/AssistantWebMemoryStore.swift` (`resetForTesting`)

## Medium-Confidence Candidates

- `College/Intelligence/ToolCallStreamParser.swift` (`ToolCallStreamParseResult`) may be inlinable/internal-only.
- `College/Intelligence/IntelligenceDebugView.swift` appears debug-only and may be intentionally retained.

## Verification note before deletion:

One pass should verify non-Swift dynamic wiring (runtime flags, string routes, UI bindings, test-only external targets) before removal.

## Test and Quality Findings

## Coverage Gaps

- `AIAssistantView` lacks deep direct behavioral tests for state transitions and persistence edge cases.
- `CoreDataManager` tests are useful but do not fully cover production-like migration/bootstrap/failure paths.

## Stability/Runtime Debt in UI Tests

- Several UI tests rely on fixed sleeps (`Thread.sleep` patterns), which can cause flakiness and slower CI.

Files with notable patterns include:
- `CollegeUITests/AssistantComprehensiveAnalysisUITests.swift`
- `CollegeUITests/AppWidePerformanceUITests.swift`
- `CollegeUITests/PressableStressUITests.swift`
- `CollegeUITests/AssistantInstrumentsSurrogateUITests.swift`
- `CollegeUITests/UITestCollegeHarness.swift`

## Likely Stale Test Scaffolding

- `CollegeTests/CollegeTests.swift`
- `CollegeUITests/CollegeUITests.swift`
- `CollegeUITests/CollegeUITestsLaunchTests.swift`

These look template-like and may be removable after confirming no workflow dependency.

## Dependency Audit (SourcePackages)

## App-Actionable

- `mlx-swift-lm` is pinned to branch `main` in `Package.resolved`.
  - Risk: unstable updates/regressions.
  - Recommendation: stable revision/tag policy with scheduled upgrade validation.

## Upstream/Monitor

- Many deprecations in MLX-family packages appear compatibility-oriented and not directly used by app import surface.
- `mlx-swift-lm` internals include synchronous file/config loading and full tensor materialization patterns that can impact cold-start and memory.

## Top 15 Risk Files

1. `College/CoreData/CoreDataManager.swift`
2. `College/Calendar/CalendarIntegrationManager.swift`
3. `College/Calendar/AddCalendarItemOverlay.swift`
4. `College/Calendar/CalendarView.swift`
5. `College/Intelligence/AIAssistantView.swift`
6. `College/App/LaunchPreloadCoordinator.swift`
7. `College/Catalog/ModernCampusEngine.swift`
8. `College/Catalog/UniversalCatalogScraper.swift`
9. `College/Courses/CourseDashboardView.swift`
10. `College/Documents/DocumentsView.swift`
11. `College/Academics/AcademicsView.swift`
12. `College/App/OnboardingRootView.swift`
13. `College/Profile/AcademicIdentityView.swift`
14. `College/Overview/OverviewView.swift`
15. `College/Services/DocumentClassifierService.swift`

## Recommended Next Step (Still No Edits)

Before code changes, define a deletion-safety matrix and optimization sequence:

- Tier 1 deletions (high confidence, low risk),
- Tier 2 deletions (single verification gate),
- Optimization wave 1 (startup + UI hitch hotspots),
- Optimization wave 2 (Core Data/query efficiency),
- Optimization wave 3 (test stability/runtime and dependency pin hygiene).

