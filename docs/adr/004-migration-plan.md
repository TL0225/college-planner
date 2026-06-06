# ADR 004 Phase 2 — Migration Plan

**Owner:** Timothy Leung  
**Deadline:** 2026-06-19  
**Status:** Phase 2 complete (Calendar Layers 1–4 + Academics/Career Layer 1 packages + package import CI)

## Audit summary (2026-06-05)

Cross-feature coupling today is **monolithic** (single app target). The import gate catches explicit module/path violations; symbol-level coupling requires package extraction to become compile-time failures.

### Import / path violations (script-detectable)

| Check | Count | Notes |
| --- | ---: | --- |
| `import College<Feature>` cross-feature | 0 | No feature packages wired yet |
| `import CollegePlatform` from Features | 2 | Calendar only — **allowed** shared dep |
| `Features/<Other>/` path references | 0 cross-feature | One intra-Catalog bundle path |
| `// cross-feature:` markers | 0 | — |

### Symbol coupling inventory (heuristic, types ≥10 chars)

Files in feature A referencing types defined in feature B:

| Source → Target | Files |
| --- | ---: |
| Assistant → SyllabusAI | 7 |
| Academics → Profile | 6 |
| Academics → Catalog | 6 |
| Assistant → Catalog | 6 |
| Catalog → Degree | 6 |
| Catalog → SyllabusAI | 6 |
| Profile → Degree | 6 |
| Settings → Calendar | 6 |
| Academics → Degree | 5 |
| Catalog → Academics | 5 |
| Profile → Catalog | 5 |
| Settings → Catalog | 5 |
| Overview → Calendar | 4 |
| Calendar → Academics | 1 |
| Calendar → Documents | 1 |
| Calendar → Settings | 1 |
| Calendar → SyllabusAI | 1 |

Calendar is the **lowest fan-in** migration candidate (4 inbound, 4 outbound file-level refs).

### Bridge files (21)

Explicit cross-feature integration surfaces to dissolve into Core/Platform protocols:

- `Features/Calendar/CalendarReadBridge.swift`
- `Features/Calendar/CalendarIntegrationBridge.swift`
- `Features/Calendar/CalendarEventSearchBridge.swift`
- `Features/Academics/AcademicsPlannerReadBridge.swift`
- `Features/Academics/AuditCatalogLookupBridge.swift`
- `Features/Overview/OverviewReadBridge.swift`
- (see `scripts/check-feature-imports.sh` audit or repo search `Bridge.swift` under Features)

## Migration order

1. **CollegeCalendar** — `Packages/CollegeCalendar/` (scaffold committed)
2. **CollegeAcademics** — `College/Features/Academics/` (28 files)
3. **CollegeCareer** — `College/Features/Career/` (56 files)

## Phase 2a — Calendar extraction file list (63 files)

Move from `College/Features/Calendar/` into `Packages/CollegeCalendar/Sources/CollegeCalendar/` in layers:

### Layer 1 — pure types (no SwiftUI, no CollegePersistence)

- `CalendarCacheEngine.swift`
- `CalendarTenantKind.swift`
- `CalendarVisibilityFilter.swift`
- `CalendarFormatters.swift`
- `CalendarTimelineAggregator.swift`
- `CalendarTimelineEpics.swift`
- `Recurrence/CalendarRecurrenceExpander.swift`
- `ICS/ICSCalendarParser.swift`

### Layer 2 — write pipeline + editor session (**complete**)

Moved to `Packages/CollegeCalendar/Sources/CollegeCalendar/Write/`:

- `CalendarEventWritePipeline.swift`, `CalendarEventWritePipeline+Overlay.swift`
- `CalendarEditorSession.swift`

Persistence writes go through `CalendarWriteRepositoryPort` / `CalendarPersistencePort` (app adapters in `College/Features/Calendar/*Port+App.swift`).

### Layer 3 — sync providers + integration manager (**complete**)

Moved to `Packages/CollegeCalendar/Sources/CollegeCalendar/`:

- `Integration/CalendarIntegrationManager.swift`, `+Export.swift`, `+StoreSync.swift`, `+SyncProviderAPI.swift`
- `Integration/CalendarSyncCoordinator.swift`, `CalendarSyncMapDiskPersistence.swift`, `AppleCalendarIntegration.swift`
- `Sync/*.swift` (Google/Apple/Outlook/iCloud providers)
- Port surface: `CalendarIntegrationPorts.swift`, `GoogleCalendarAuthPort.swift`, `CalendarIntegrationBridge.swift`

App bridges: `CalendarIntegrationPorts+App.swift`, `GoogleCalendarAuthPort+App.swift`, ingest via `CalendarSyncIngestService` (SwiftData stays in app).

### Layer 4 — UI (**complete**; heavy overlays remain in app)

Moved to `Packages/CollegeCalendar/Sources/CollegeCalendar/UI/` and `Views/`, `Editor/`:

- `CalendarView.swift`, `CalendarSceneState.swift`, `CalendarEnvironment.swift`, `CalendarShellPorts.swift`
- Grid/views: `CalendarWeekPlannerView.swift`, `CalendarDayHeader.swift`, `CalendarEventChipStyle.swift`, …
- Editor chrome: `CalendarEditorPresentation.swift`, `CalendarEditorAnchor.swift`, `CalendarGridPopoverMetrics.swift`

**Stays in app** (SwiftData / `AppContainer` / catalog coupling):

- `AddCalendarItemOverlay.swift`, `AddTaskOverlay.swift`, `CalendarModalHost.swift`, `CalendarGridEditorHost.swift`
- `CalendarEventEditorPopover.swift`, `CalendarEventEditorSheet.swift`, `NewEventModal.swift`
- `Views/CalendarGhostEventOverlay.swift`
- Bridges: `CalendarPersistencePort+App.swift`, `CalendarReadPort+App.swift`, `CalendarShellPorts+App.swift`, `CalendarOverlayPort+App.swift`, `CalendarPersistenceBridges.swift`, `CalendarReadBridge.swift`, …

## Package scaffolds

| Path | Purpose |
| --- | --- |
| `Packages/CollegeCalendar/` | First feature module; depends on `CollegePlatform` |
| `Packages/CollegePlatformBoundary/` | Documents allowed dependency edges |
| `CollegePlatform/` | Existing shared module (calendar change messaging, integration health) |

## Xcode wiring (Phase 2a — 2026-06-05)

1. [x] Add local package reference `Packages/CollegeCalendar` to `College.xcodeproj` (`XCLocalSwiftPackageReference`, mirrors `CollegePlatform`)
2. [x] Link `CollegeCalendar` product to College app target and `CollegeTests`
3. [x] Layer 1 sources removed from app compile path (moved to package; SwiftData bridges remain in app)
4. [x] Repeat for Academics/Career (Layer 1 packages wired; scrapers/UI remain in app)

### Layer 1 status: **complete**

Moved to `Packages/CollegeCalendar/Sources/CollegeCalendar/`:

| File | Notes |
| --- | --- |
| `CalendarCacheEngine.swift` | Pure cache engine + snapshot types |
| `CalendarTenantKind.swift` | Uses `CoreGraphics`; persistence `resolve(for:)` in app bridge |
| `CalendarVisibilityFilter.swift` | Uses `CalendarVisibilityEventInput`; SwiftData `shouldDisplay(_: CalendarEvent)` in app bridge |
| `CalendarFormatters.swift` | Date formatters |
| `CalendarTimelineAggregator.swift` | Tenant enrichment via `[UUID: CalendarTenantKind]` map |
| `CalendarTimelineEpics.swift` | Dependency / display-mode foundation types |
| `Recurrence/CalendarRecurrenceExpander.swift` | EventKit + RRULE fallback |
| `ICS/ICSCalendarParser.swift` | Minimal ICS parser |

App-target bridges (Layer 2 prep, not Layer 1):

- `CalendarFetchQuery.swift` — SwiftData fetch helpers (split from former `CalendarVisibilityFilter.swift`)
- `CalendarPersistenceBridges.swift` — `CalendarEvent` adapters for package APIs

Tests: `Packages/CollegeCalendar/Tests/CollegeCalendarTests/CalendarCacheEngineTests.swift` (perf + ICS smoke).

**Remaining follow-ups (post Layers 1–4):**

- Move additional Calendar unit tests from `CollegeTests/Features/Calendar/` into `Packages/CollegeCalendar/Tests/`
- No `CollegeCore` package yet; SwiftData models (`CalendarEvent`, `PlannerTask`) remain in app
- `CalendarGhostEventOverlay` stays in app until editor host is fully port-driven

## Phase 2b — CollegeAcademics (Layer 1 + scene state)

Package: `Packages/CollegeAcademics/`

| Moved to package | Stays in app |
| --- | --- |
| `GPAFormatting.swift` | Requirement engines (Catalog coupling) |
| `GraduationTimelineEngine.swift` | Views, stores, bridges |
| `AuditRequirementSelectionStore.swift` | `GraduationTimelinePolicyBridge.swift` |
| `UI/AcademicsSceneState.swift` | SwiftData / Catalog DTO adapters |

## Phase 2c — CollegeCareer (Layer 1 + scene state)

Package: `Packages/CollegeCareer/`

| Moved to package | Stays in app |
| --- | --- |
| `CareerModels.swift` (DTOs) | Scrapers, Workday sync, views |
| `JobPostingEnrichment.swift` | `JobBoardScraper.swift`, platform detectors |
| `CareerNavigation.swift` (`CareerSubView`, `CareerBoardLayout`) | `CareerBoardLayoutMenu`, workspace UI |
| `UI/CareerSceneState.swift` | SwiftData bridges, ingest/AI |

## CI

- `scripts/check-feature-imports.sh warn` — toolbar-architecture workflow (interim)
- `scripts/check-feature-imports.sh fail` — `feature-boundaries.yml` PR gate
- Legacy allowlist: empty (no suppressions needed at kickoff)

## Exit criteria (from ADR 004)

- [x] `feature-boundaries.yml` exists and runs fail mode
- [x] `import CollegeAcademics` inside `CollegeCalendar` sources fails CI (`check-feature-imports.sh` scans `Packages/`)
- [x] Calendar package extracted (Layers 1–4); Academics and Career Layer 1 packages follow
