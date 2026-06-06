# ADR 004 Phase 2 — Migration Plan

**Owner:** Timothy Leung  
**Deadline:** 2026-06-19  
**Status:** Phase 2a in progress (Layer 1 complete, package wired)

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

### Layer 2 — platform messaging (already in CollegePlatform)

- `CalendarEventWritePipeline.swift` (uses `CalendarChangePublisher`, `IntegrationHealthStore`)
- `CalendarEditorSession.swift`

### Layer 3 — sync providers + integration manager

- `Sync/*.swift`
- `CalendarIntegrationManager*.swift`
- `CalendarSyncCoordinator.swift`
- `CalendarSyncMapDiskPersistence.swift`

### Layer 4 — UI (last; depends on App shell + bridges)

- `CalendarView.swift`
- `Views/*.swift`
- `Editor/*.swift`
- Modals/overlays (`NewEventModal.swift`, `AddTaskOverlay.swift`, …)

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
4. [ ] Repeat for Academics/Career

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

**Blockers for full Calendar extraction:**

- Layer 2: `CalendarEventWritePipeline`, `CalendarEditorSession` (CollegePlatform messaging; persistence writes)
- Layer 3: Sync providers, `CalendarIntegrationManager*`, coordinators (~20 files; heavy SwiftData + EventKit)
- Layer 4: SwiftUI views, editor, modals (depend on App shell + `@Environment` bridges)
- `CalendarView.swift` still duplicates private `CalendarFormatters` — dedupe when UI moves
- No `CollegeCore` package yet; persistence models stay in app until Core extraction lands

**Blocker note:** Full Calendar extract in one pass risks breaking SwiftUI previews and bridge compile order. Layer 1–2 can land without UI churn.

## CI

- `scripts/check-feature-imports.sh warn` — toolbar-architecture workflow (interim)
- `scripts/check-feature-imports.sh fail` — `feature-boundaries.yml` PR gate
- Legacy allowlist: empty (no suppressions needed at kickoff)

## Exit criteria (from ADR 004)

- [x] `feature-boundaries.yml` exists and runs fail mode
- [ ] `import CollegeAcademics` inside Calendar fails CI (requires packages + app wiring)
- [ ] Calendar package extracted; Academics and Career follow
