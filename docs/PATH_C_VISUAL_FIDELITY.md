# Path C — Screen-by-screen visual fidelity (Swift → Tauri)

**Goal:** Copy Swift UI composition into the Tauri React app **screen by screen** — same hierarchy, chrome, density, and charts as far as WebView allows. Not “workflow substitutes only.”

**Source of truth:** SwiftUI under `College/Features/` + `Packages/*/UI/`.  
**Target:** `CollegeDesktop/src/modules/` + `CollegeDesktop/src/design-system/`.

Platform APIs that cannot exist in WebView (EventKit FFI, MapKit NSView, MLX Metal, Share Extension) still need the closest visual + behavioral stand-in, but **layouts must match Swift**, not a thin card grid.

## Path D — Reference-app IA (2026)

Path D supersedes the 7-hub pill bar for `CollegeDesktop`. See `docs/COPY_STYLE.md` and `docs/OVERHAUL_AUDIT.md`.

| Hub | Replaces |
|-----|----------|
| Home | College Overview default |
| School | college academics + catalog + discovery + transfer + LMS |
| Life | finance + calendar |
| Library | documents + profile |
| Career | career (sidebar: Pipeline · Pathing · Resume · Growth) |

Assistant is an omnipresent slide-over (⌘J / sparkles FAB). Settings remains sidebar-footer + gear.

Migration: `shell.iaVersion=2` in `lib/shell/migration.ts`.

---

1. Open the Swift screen.
2. Port structure (headers, rows, inspectors, empty states, spacing) into React using design-system primitives.
3. Diff visually in `cd CollegeDesktop && bun run tauri:dev` (or repo-root `bun run tauri:dev`) next to the Swift app.
4. Mark the screen **Done** below only when composition matches (not when IPC merely works).

## Screen checklist

| # | Swift surface | React target | Status |
|---|---------------|--------------|--------|
| 1 | Overview widget kit + dashboard grid | `OverviewWidgets.tsx` + `OverviewWidgetKit` | **Done (v1)** |
| 2 | Finance dashboard + Charts | `FinanceDashboardScreen.tsx` | **Done (v1)** |
| 3 | Finance account detail (Chase summary) | `FinanceAccountDetailScreen.tsx` | **Done (v1)** |
| 4 | Finance reports / assets charts | `FinanceReportsScreen.tsx` | **Done (v1)** |
| 5 | Academics planner canvas | `PlannerCanvas.tsx` | **Done (v1)** |
| 6 | Course dashboard | `CourseDashboard.tsx` + `CourseDashboardKit.tsx` | **Done (v1)** |
| 7 | Degree / requirements | `DegreeRequirementsScreen.tsx` | **Done (v1)** |
| 8 | Calendar month / week / day | `CalendarModule.tsx` + `MonthGrid`/`WeekGrid`/`DayTimeline` | **Done (v1)** |
| 9 | Calendar event editor + map | `CalendarModule.tsx` + `EventLocationMap.tsx` | **Done (v1)** |
| 10 | Career applications board | `CareerModule.tsx` + `KanbanLaneHeader` | **Done (v1)** |
| 11 | Career Pathing hub + timeline | `CareerModule.tsx` + `PathTimeline` panels | **Done (v1)** |
| 12 | Career stats Charts | `CareerModule.tsx` stats view | **Done (v1)** |
| 13 | Job board lanes | `CareerModule.tsx` openings | **Done (v1)** |
| 14 | Documents vault / Finder-like | `DocumentsModule.tsx` | **Done (v1)** |
| 15 | Discovery school profile | `DiscoverySchoolProfile.tsx` | **Done (v1)** |
| 16 | Catalog browser | `CatalogModule.tsx` | **Done (v1)** |
| 17 | Transfer | `TransferModule.tsx` | **Done (v1)** |
| 18 | LMS | `LmsModule.tsx` | **Done (v1)** |
| 19 | Assistant chat + syllabus | `AssistantModule.tsx` | **Done (v1)** |
| 20 | Profile / identity | `ProfileModule.tsx` | **Done (v1)** |
| 21 | Resume builder | `ResumeLiveBuilder.tsx` / Career resume | **Done (v1)** |
| 22 | Settings panes | `SettingsModule.tsx` | **Done (v1)** |
| 23 | Hub launcher | `HubLauncher.tsx` + `HubModuleTile` | **Done (v1)** |
| 24 | Design-system sheets / forms / amount hero | `PathCChrome.tsx` | **Done (v1)** |

## Pass notes

### Pass 1 — Overview widget kit

Port Swift `College/Features/Overview/WidgetKit/OverviewCard.swift`:

- `OverviewWidgetHeader`, empty/row/badge surfaces, adaptive ~340px grid

### Pass 2 — Finance dashboard

Port Swift `FinanceDashboardView`: hero metrics, net-worth trend, cash-flow bars, accounts column, recent transactions.

### Pass 3 — Planner canvas + course dashboard

Port `AcademicsSemesterCanvasView` and `CourseDashboardScreen+Sections.swift` (vertical semester list; flat course page sections).

### Pass 4 — Finance account + reports

Port `FinanceChaseAccountSummary.swift` → layered chart card, category donut, monthly flow stats.  
Port `FinanceReportsView.swift` → segmented report kind, date range, primary chart + “More reports” disclosure.

### Pass 5 — Degree requirements

Port `AcademicsAuditPanel` composition → `DegreeRequirementsScreen.tsx` with breakdown rows, bottom program strip, drag-to-fulfill.

### Pass 6 — Shared Path C chrome

`CollegeDesktop/src/design-system/components/PathCChrome.tsx`:

- `FlatSectionTitle`, `FormAmountHero`, `InsetChartCard`
- `FinderToolbarRow`, `KanbanLaneHeader`, `HubModuleTile`, `PathCScreenFrame`, `SettingsPaneShell`

Applied across hub launcher, career board lanes, and module screen frames.

## Related

- [UI_CATALOG.md](UI_CATALOG.md)
- [DESKTOP_TAURI.md](DESKTOP_TAURI.md)
