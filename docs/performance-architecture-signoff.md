# Performance architecture sign-off (Jun 2026)

Locked boundaries after the local store cutover and Phase 8 `@Observable` shell migration.

## Catalog sync (`CatalogBackgroundSyncRunner`)

| Layer | Isolation | Notes |
|-------|-----------|--------|
| UI hooks, toasts, checkpoints, local store commit | `@MainActor` | Intentional — keeps ingest state aligned with AppKit progress UI |
| HTTP download | `nonisolated` | `downloadToTemporaryFileWithProgress` streams to disk |
| Modern Campus Phase B scrape | `nonisolated` | `scrapeModernCampusPhaseBCourses`; merge on main |
| PDF page parse | `Task.detached` | `CatalogPDFPipeline.run`; progress callbacks hop to main |

In-memory `downloadDataWithProgress` was removed — all remote PDFs use temp-file streaming.

## Observation model (Phase 8)

| Type | Pattern | Rationale |
|------|---------|-----------|
| Shell coordinators | `@Observable` + `.environment()` | `LaunchPreloadCoordinator`, `ModalCoordinator`, `AppToolbarCoordinator`, `AppActivityCoordinator`, `WidgetRegistry`, menu-bar/career/settings stores |
| `CollegePersistence` | `ObservableObject` (singleton) | Large surface; local store + `@Query` migration is the observation path for UI |
| `CalendarIntegrationManager` | `ObservableObject` (singleton) | EventKit + sync; migrate only with a dedicated calendar observation bridge |
| `AppDataStore` / `SecurityManager` | `ObservableObject` | App-lifetime services; low invalidation fan-out via environment |

## Rust / embed (Phase 9)

- **Rust:** Optional `libcollege_core.a`; see [`rust-embed-phase9.md`](rust-embed-phase9.md). `CollegeCoreSwiftRegressionTests` covers Swift fallbacks.
- **Catalog embed:** MLX via `CatalogEmbeddingRuntime` + `MLXTaskQueue`; not Rust FFI.

## Release unit tests

- `ENABLE_TESTABILITY = YES` on the **College** Release target so `CollegeTests` can `@testable import College`.
- `COLLEGE_TEST_HOOKS` (Release only, paired with testability) compiles internal `_forTests` / `testSystemLanguageModelAvailable` helpers that are otherwise `#if DEBUG`.
- App Store archives should use a distribution configuration without `COLLEGE_TEST_HOOKS` if you need a hook-free Release binary.
- Verified Jun 2026: full `CollegeTests` **287 run / 0 failures / 10 skipped** in Release (`xcodebuild test -configuration Release`).
- CI helper: `./scripts/run-performance-gates.sh` (Debug full suite) or `Release` (perf + schema subset).

## RSS / Instruments

Recorded samples live in [`performance-baseline.md`](performance-baseline.md). Signpost durations (`LoadAudit`, `LLMUnload`, `CatalogVectorReindex`) require a full Instruments POI trace when reproducing those flows.
