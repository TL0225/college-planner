# Swift Performance Bottleneck Register

Date: 2026-04-27

This register implements the bottleneck analysis track from the audit plan. Items are ordered by expected user-visible impact.

## Critical

### `College/Services/StaleFileMonitor.swift`

- Risk: main-thread filesystem enumeration and file metadata checks.
- Likely impact: UI hitches when watched folders are large.
- Optimization:
  - move scanning off `@MainActor`,
  - stream enumeration instead of materializing all paths,
  - chunk scans and debounce notifications,
  - publish only summary state back to main actor.
- Validation:
  - Instruments hitches trace during scan,
  - manual large-folder scan smoke,
  - Debug build and relevant feature smoke.

### `College/CoreData/CoreDataManager.swift`

- Risk: repeated Core Data fetches and reduce/count work in import/requirement paths.
- Likely impact: import/sync latency, SQLite round trips, memory pressure.
- Optimization:
  - prefetch rows once into dictionaries keyed by stable identifiers,
  - replace fetch-for-count with `count(for:)`,
  - batch writes and saves,
  - move expensive IO/decrypt/write paths off main actor.
- Validation:
  - import baseline timing,
  - Core Data regression tests,
  - catalog/search smoke.

## High

### `College/Courses/CourseSearchView.swift`

- Risk: interactive search can trigger heavy query/backfill behavior.
- Likely impact: typing latency and UI responsiveness issues.
- Optimization:
  - keep live search read-only,
  - move backfill/precompute work to import/background stage,
  - return lightweight DTOs to UI.

### `College/Calendar/CalendarView.swift`

- Risk: cache rebuilds can be triggered repeatedly by independent changes.
- Likely impact: CPU churn and frame pacing issues.
- Optimization:
  - coalesce invalidations,
  - use visible-range gating,
  - rebuild incrementally where possible.

### `College/Catalog/ModernCampusEngine.swift`

- Risk: repeated parsing/network/catalog normalization work.
- Likely impact: catalog ingestion latency.
- Optimization:
  - avoid repeated reparsing of unchanged documents,
  - cap parallelism,
  - cache parsed page metadata with invalidation.

### `College/Catalog/UniversalCatalogScraper.swift`

- Risk: overlapping catalog scraping responsibilities and fallback data quality path.
- Likely impact: slower catalog extraction and inconsistent results.
- Optimization:
  - consolidate with primary catalog engine,
  - reduce duplicate parse/fetch logic.

### `SourcePackages/checkouts/mlx-swift-lm`

- Risk: model load path includes synchronous config reads and broad weight materialization.
- Likely impact: cold-start latency and memory spikes.
- Optimization:
  - app-side prewarm and avoid cold load in interaction path,
  - monitor upstream for streaming/incremental load support,
  - pin dependency to stable revision/tag.

## Medium

### `College/App/LaunchPreloadCoordinator.swift`

- Risk: polling loops with fixed sleeps.
- Optimization:
  - replace with event/state-driven continuations where possible.

### `College/App/LaunchUpdateCheckService.swift`

- Risk: repeated session/decoder setup and synchronous reads.
- Optimization:
  - reuse session/decoder,
  - cache manifest parse result,
  - move file reads off startup hot path.

### `College/Intelligence/AIAssistantView.swift`

- Risk: large SwiftUI body, broad state fan-out, frequent persistence/scroll reactions.
- Optimization:
  - split stable subviews,
  - isolate streaming message updates,
  - coalesce persistence writes.

### `College/Brightspace/BrightspaceWebCoordinator.swift`

- Risk: frequent KVO-to-task hops.
- Optimization:
  - coalesce observer updates,
  - avoid creating one task per high-frequency KVO event.

### `College/WebShortcuts/ShortcutWebCoordinator.swift`

- Risk: frequent KVO-to-task hops.
- Optimization:
  - share a web coordinator pattern with throttled state updates.

## Batch Coverage

- Batch-level performance notes are represented in `SWIFT_FILE_AUDIT_LEDGER.csv`.
- Primary optimization waves are:
  1. main-thread filesystem and IO,
  2. Core Data fetch/write efficiency,
  3. UI recomposition/cache invalidation,
  4. dependency/model-load cold-start risk,
  5. tests/CI runtime stabilization.

