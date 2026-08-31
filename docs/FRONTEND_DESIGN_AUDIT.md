# Front-End Design Audit (Page-by-Page)

Audit-only pass. **No source files were changed while producing this document.**

Related: [MCP_FRONTEND_AUDIT.md](./MCP_FRONTEND_AUDIT.md) covers MCP-server component sourcing (Tooltip, Switch, etc.). This document covers **layout, information hierarchy, digestibility, and visual polish** — why the app feels "placed in" rather than intentionally designed.

---

## Method and design direction

### What we evaluated (every screen)

1. **Information digestibility** — Can an average, non-technical user scan this screen in ~5 seconds and know what it is and what to do next?
2. **Visual polish** — Does the screen look intentionally designed (clear hierarchy, consistent spacing, one primary action), or assembled from unrelated pieces (duplicate data, dead controls, dev-facing copy, ad hoc inline styles)?

### Design direction (per user)

- **Cross-platform** — not constrained to macOS/Swift-parity. Reference patterns are chosen per screen type from modern production apps.
- **One shared design system** — consistency across hubs matters more than matching any single reference app everywhere. The app's own tokens (`--type-*`, `--color-*`) and primitives (`AppCard`, `MetricTile`, `TrailingInspector`, `SegmentedPills`) should be applied uniformly; where they aren't, that's a polish finding.
- **Super-app intent** — multiple sub-apps (School, Career, Life, Library, Assistant) in one shell, cross-linked via deep links and shared data. Cross-hub **linking** is good; cross-hub **content duplication** (rendering another hub's page verbatim) is not.

### Reference patterns used (per screen type)

| Screen type | Reference pattern | What they do better |
|-------------|-------------------|---------------------|
| Home / dashboard | Notion Home, Linear inbox | Content first; 4–6 curated cards max; nav second |
| Command palette | Raycast, Linear, VS Code | Sticky group headers; search-first; actions over nav duplication |
| Calendar | Fantastical, Notion Calendar | One header tier; today/up-next summary above grid |
| Kanban / pipeline | Linear, Trello | Metric strip + board; inspector on right; no duplicate stats page |
| Settings forms | Stripe, Linear | Toggle rows; one card = one concern; no empty cards |
| File browser | Finder, Notion | Toolbar overflow menu; breadcrumbs; inspector |
| Finance dashboard | Monarch, Copilot | Hero metric + 2–3 supporting cards; CTAs go somewhere real |
| Chat / AI panel | Cursor, Notion AI | Conversation-first in slide-over; citations on answers |
| Academic planner | DegreeWorks + semester timeline | Degree audit separate from semester canvas; courses ≠ plan |

---

## Summary table

| # | Surface | Screens audited | Digestibility | Polish | Top issue | Priority |
|---|---------|-----------------|---------------|--------|-----------|----------|
| 1 | Shell chrome & navigation | 6 (layout, pills, sidebar, palette, hub launcher, AI FAB) | Medium | Medium | Triple hub navigation; shortcuts hidden | P0 |
| 2 | Home hub | 4 sidebar pages (3 dead) | **Poor** | **Poor** | Dead tabs; School overview borrowed; widget kitchen sink | **P0** |
| 3 | School hub | 7 areas + req-* deep links | Mixed | Mixed–Good | Discover sidebar → Catalog, not Discovery; no School Overview | **P0** |
| 4 | Life hub | 5 sidebar + finance sub-pages + orphans | Good–Mixed | Good (finance) / Dense (calendar) | Dashboard CTAs dead-end; orphan Ledger/Goals screens | **P0** |
| 5 | Library hub | 7 sidebar + folder/course deep links | Good | Good | Experiences/Achievements unreachable; category gaps | **P0** |
| 6 | Career hub | 11 views | Good (pipeline) / **Poor** (pathing) | Mixed | 17 flat Pathing tabs; Growth double header | **P0** |
| 7 | Settings | 12 pages | Good structure / uneven depth | Mixed | Empty Finance card; raw checkboxes; Profile stub | P1 |
| 8 | Assistant | Chat panel + syllabus | **Poor** (panel) / Good (syllabus) | Mixed | Panel overloaded; no citations; syllabus unreachable from FAB | **P0** |
| 9 | Design system (cross-cutting) | Primitives across all screens | — | Inconsistent | `EmptyState` in `Button.tsx`; inline `fontSize` in 32+ files; no Toggle | P1 |

---

## 1. Shell chrome & navigation

### Screens audited

Shell layout (`ShellSplitLayout.tsx` + `App.tsx` header), Module pill bar, App sidebar (Home context), Command palette, Hub launcher, AI panel + FAB.

### Current state

Solid super-app skeleton: logo cell | pill bar | search/hubs/settings | sidebar + content. Motion on pills and sidebar selection is polished. Window chrome is custom undecorated (Windows DWM).

### Digestibility issues

| ID | Screen | Issue | Citation |
|----|--------|-------|----------|
| SH-1 | Header | Four competing affordances (pills, Search, Hubs, Settings) with no page/breadcrumb context | `App.tsx` ~770–811 |
| SH-2 | Command palette | Empty query dumps recents + all hubs + actions + live IPC with **no visual group headers** — hard to scan | `CommandPalette.tsx` ~164–167; `App.tsx` ~614–721 |
| SH-3 | Hub launcher | Mirrors pill bar exactly — user must learn two identical nav surfaces | `HubLauncher.tsx` 6–17; `App.tsx` 102–108 |

### Polish issues

| ID | Screen | Issue | Citation |
|----|--------|-------|----------|
| SH-4 | Pills | Settings shows Home pill as selected — misleading active hub | `App.tsx` ~774 |
| SH-5 | Pills | `⌘1–5` hub shortcuts exist but pills show no hint | `App.tsx` 381–392 |
| SH-6 | Chrome | Keyboard shortcuts mostly hidden — only Search shows `⌘K`; Hubs `⇧⌘H`, AI `⌘J` undocumented | `App.tsx` 360–392, 786–797 |
| SH-7 | Logo | Generic "C" monogram — prototype feel | `ShellSplitLayout.tsx` 52–64 |
| SH-8 | Sidebar | Auto-collapses `<1024px` only; no manual collapse toggle | `useShellLayout.ts` 55 |

### Reference & recommendations

| ID | Priority | Recommendation |
|----|----------|----------------|
| SH-1 | P1 | Add breadcrumb or page title in header (Linear pattern) |
| SH-2 | P1 | Render `group` as sticky section headers with separators (Raycast) |
| SH-3 | **P0** | Remove Hub Launcher or repurpose for deep destinations (Settings, Assistant, sub-pages) — not duplicate of pills |
| SH-4 | P1 | Neutral pill selection in Settings, or add Settings as 6th pill |
| SH-5 | P2 | Subtle `1–5` badges on pills |
| SH-6 | P1 | Show shortcut hints on Hubs and AI entry points |
| SH-7 | P2 | Replace with real product mark |

---

## 2. Home hub

### Screens audited

Today, Week, Goals, Recents (sidebar); header strip; embedded overview widgets.

### Current state

`HomeModule.tsx` gates on four page IDs but renders **one hardcoded path**: title always "Today", body always `<AcademicsModule page="academics" hideChrome />` (School's full overview widget grid). Header adds four `HubModuleTile`s (duplicate of pill bar) plus Search / Add event / Log expense.

### Digestibility issues

| ID | Screen | Issue | Citation |
|----|--------|-------|----------|
| HM-1 | All sidebar tabs | **Week, Goals, Recents are non-functional** — selection changes highlight only | `App.tsx` 417–420; `HomeModule.tsx` 24–36, 36 |
| HM-2 | Today | **~16 widgets default-on** — academic-heavy kitchen sink, not a "Today" glance | `OverviewWidgets.tsx` 174–193, 1320–1354 |
| HM-3 | Today | GPA/credits shown **3×** (Academic Calendar, Academic Journey, GPA widgets) | `OverviewWidgets.tsx` 232–346, 370–405 |
| HM-4 | Today | Career duplicated (Pipeline + Summary); Documents duplicated; Tasks triplicated (Deadlines, Open Tasks, Needs Attention) | `OverviewWidgets.tsx` 471+, 656+, 697+, 885+, 985+ |
| HM-5 | Today | Quick Launch widget duplicates hub tiles + pill bar (6 shortcuts) | `OverviewWidgets.tsx` 205–212, 513–556; `HomeModule.tsx` 50–83 |

### Polish issues

| ID | Screen | Issue | Citation |
|----|--------|-------|----------|
| HM-6 | Today | **Borrowed School overview** — customize copy says "School Overview"; settings key `dashboard.widgets.v1` | `HomeModule.tsx` 86–87; `OverviewWidgets.tsx` 1357–1360 |
| HM-7 | Header | Hub tiles push real content below fold — nav before signal (inverted vs Notion Home) | `HomeModule.tsx` 33–88 |
| HM-8 | Widgets | "Academic Calendar" widget shows credits/GPA, not calendar events — mislabeled | `OverviewWidgets.tsx` 370–405 |
| HM-9 | Recents | Sidebar "Recents" duplicates command palette Recents group; neither wired to `recents` state in sidebar | `App.tsx` 310–313, 614–621 |

### Reference & recommendations

**Target layout (Notion Home + Linear triage):**

```
[Today — date]                    [+ Quick add] [⌘K]
┌─────────────────┬─────────────────┐
│ Today's schedule│ Due / attention │
├─────────────────┴─────────────────┤
│ Week ahead (events)               │
└───────────────────────────────────┘
```

| ID | Priority | Recommendation |
|----|----------|----------------|
| HM-1 | **P0** | Implement distinct views per tab or remove stubs |
| HM-2 | **P0** | New `HomeWidgetGrid` — max 5 default widgets (schedule, due tasks, week ahead, one hub summary) |
| HM-3 | **P0** | Stop embedding `AcademicsModule` overview; keep academics widgets in School only |
| HM-4 | **P0** | Remove duplicate hub tile row from Home header |
| HM-5 | P1 | Wire Recents tab to existing `recents: ShellRecent[]` in `App.tsx` |
| HM-6 | P1 | Deduplicate GPA/career/documents/tasks widgets |
| HM-7 | P2 | Defer weather widget until opt-in; rename mislabeled widgets |

---

## 3. School hub

### Screens audited

Overview (Home-only today), Plan, Courses, Degree + req-* deep links, Discover, Transfer, LMS; plus orphaned Discovery module.

### Cross-cutting IA (P0)

| Issue | Citation |
|-------|----------|
| **Discover sidebar → CatalogModule**, not DiscoveryModule | `SchoolModule.tsx` 12–17: `page === "discover"` → Catalog; `discovery` page not in sidebar |
| **Plan + Courses are identical** — both map to planner view | `SchoolModule.tsx`; sidebar in `App.tsx` |
| **No School Overview** in sidebar — overview only on Home | `HomeModule.tsx` 86–87 |

### Screen-by-screen

#### 3.1 Academics Overview (Home-only)

- **Digestibility:** Mixed — widget grid is scannable but ~17 cross-hub widgets dilute School context.
- **Polish:** Strong widget shells; `GettingStartedWidget` good onboarding.
- **Findings:** OV-1 **P0** no School route; OV-2 **P1** credit ring math misleading; OV-3 **P1** cross-hub widget noise.
- **Reference:** Trim to School-focused overview on School sidebar.

#### 3.2 Planner (Plan / Courses)

- **Digestibility:** Good — semester accordion + credit totals clear.
- **Polish:** Solid; semester edit is toast stub (`PlannerCanvas.tsx` 235–238).
- **Findings:** PL-1 **P1** Plan ≡ Courses; PL-2 **P1** semester edit non-functional; PL-4 **P2** requirement chips capped at 24.
- **Candidate page:** **Courses** — flat course list distinct from semester timeline.

#### 3.3 Degree Requirements

- **Digestibility:** **Best School screen** — metric strip → progress → section cards → sticky nav.
- **Polish:** High — `PathCScreenFrame`, drop targets, deep-link scroll.
- **Findings:** DR-1 **P1** ProgramBrowser pushes audit below fold; DR-2 **P2** "Requirements" vs sidebar "Degree" label mismatch.
- **Reference:** **Template for other School screens.**

#### 3.4 Catalog (at sidebar "Discover")

- **Digestibility:** Poor for students — admin sync/scrape panels below browse.
- **Polish:** Functional list + inspector; double chrome (`ContentToolbar` + `AppPageHeader`).
- **Findings:** CA-1 **P0** labeled Discover but is course catalog; CA-2 **P1** admin tools on student path.
- **Candidate pages:** **Catalog** (browse) vs **Catalog admin** (Settings).

#### 3.5 Discovery (orphaned)

- **Digestibility:** Good — SegmentedPills modes (Discover/Profile/Compare/Saved).
- **Polish:** Strong school cards + compare table.
- **Findings:** DI-1 **P0** not in sidebar; DI-2 **P1** raw settings key in UI; DI-3 **P1** tuition filter uses stub constant.
- **Candidate page:** **Schools** sidebar entry → `DiscoveryModule`.

#### 3.6 Transfer

- **Digestibility:** **Excellent** — metrics + degree impact + equivalency list.
- **Polish:** High — import flows, proof linking.
- **Findings:** TR-1 **P1** sample mode doesn't filter when rows exist.
- **Reference:** **Strongest School screen** — benchmark for Catalog admin extraction.

#### 3.7 LMS

- **Digestibility:** Moderate — portal list clear; inspector has **12+ buttons** in one row.
- **Polish:** Good portal detection; iframe blank-state honest.
- **Findings:** LM-1 **P1** inspector action overload; LM-2 **P1** nav controls undiscoverable until window opened.
- **Candidate page:** **LMS session** — dedicated window view.

### Suggested School IA

```
School
├── Overview        ← trimmed academics widget grid
├── Plan            ← semester timeline
├── Courses         ← distinct course registry (new)
├── Degree          ← requirements + req-* deep links
├── Schools         ← DiscoveryModule (rename from buried route)
├── Catalog         ← browse only
├── Transfer
└── LMS
```

---

## 4. Life hub

### Screens audited

Schedule (month), Week, Day, Tasks, calendar sources (dynamic), Money (dashboard), account detail (dynamic), Budgets, Reports; plus orphan Ledger, Goals, Inventory, Receipts, Net Worth.

### Cross-cutting

| Issue | Priority | Citation |
|-------|----------|----------|
| Double chrome: hub `ContentToolbar` + child `AppPageHeader` | P1 | `LifeModule.tsx` 33–43; `CalendarModule.tsx` 690–755 |
| Finance dashboard "View all" CTAs both navigate to `money` (same page) | **P0** | `FinanceDashboardScreen.tsx`; `FinanceModule.tsx` 466–467 |
| Ledger, Goals, Inventory, Receipts built but no sidebar path | **P0** | `FinanceModule.tsx`; `migration.ts` 32–41 |

### Screen highlights

| Screen | Digestibility | Polish | Top finding |
|--------|---------------|--------|-------------|
| Schedule (month) | Medium | Medium-high | P1: collapse header actions into Manage menu |
| Week / Day | Good | Medium | P2: week-at-a-glance strip |
| Tasks | Medium-low | Medium | P1: two stacked cards; per-row button clutter |
| Money dashboard | **High** | **High** | **Gold standard** for hub screens (`PathCScreenFrame`) |
| Account detail | High | High | Best Life inspector |
| Budgets | Medium-high | Medium | P0: no edit flow (add + delete only) |
| Reports | High | High | P1: date range doesn't affect net-worth tab |

### Candidate new pages

- **Ledger** — restore transaction list; fix dashboard CTAs
- **Goals** — separate from budgets
- **Agenda** — implemented view, not in sidebar
- **Life overview** — today schedule + money snapshot

---

## 5. Library hub

### Screens audited

All files, Recent, Starred, Needs review, General, Syllabus, Portfolio, Identity; folder/course deep links.

### Cross-cutting

| Issue | Priority | Citation |
|-------|----------|----------|
| Experiences/Achievements screens exist but **no sidebar** — Portfolio empty states reference them | **P0** | `ProfileModule.tsx` 537, 554; `migration.ts` 56–61 |
| Transcript, Resume, Receipt categories in code but not sidebar | P1 | `DocumentsModule.tsx` 39; `App.tsx` 485–486 |
| Double chrome (hub toolbar + module header) | P1 | `LibraryModule.tsx`; `DocumentsModule.tsx` |

### Screen highlights

| Screen | Digestibility | Polish | Top finding |
|--------|---------------|--------|-------------|
| All files | Medium-high | **High** | **Gold standard** for Library; toolbar crowded (7 controls) |
| Recent / Starred | High | Medium-high | Good filter-preset pattern |
| Portfolio | High | High | Best Profile view; depends on unreachable Experiences |
| Identity | High | Medium-high | P1: advisor checklist unreachable |
| Course folder | Medium | Medium | P1: heuristic string match vs course metadata |

### Candidate new pages

- **Experiences**, **Achievements** — restore sidebar (Portfolio depends on them)
- **Advisor prep** — checklist exists, linked from School widget
- **Transcript / Resume / Receipt** — complete category coverage

---

## 6. Career hub

### Screens audited

Pipeline, Openings, Pathing, Resumes, Growth (Brag / Networking / Interview), Stats, Apply; plus modals and pathing panels.

### Cross-cutting

| Issue | Priority | Citation |
|-------|----------|----------|
| Pathing inspector: **17 flat tabs** in one `SegmentedPills` row | **P0** | `CareerPathingView.tsx` (~1,615 LOC) |
| Growth renders **double header** (`CareerGrowthView` + nested `CareerPageHeader`) | P1 | `CareerGrowthView.tsx`; `CareerModule.tsx` |
| Apply view is stub (two nav buttons, no autofill preview) | P1 | `CareerApplyView.tsx` |

### Screen highlights

| Screen | Digestibility | Polish | Reference |
|--------|---------------|--------|-----------|
| Pipeline | **Good** | High | Linear kanban — metric strip + board + inspector |
| Openings | Fair | Medium | P1: custom scope chips vs `SegmentedPills` |
| Pathing | **Poor** | Medium | P0: tab IA; split into grouped nav |
| Resumes | Fair | Medium | Dense but sectioned |
| Brag | Good | Low | P1: hand-rolled cards vs `AppCard` |
| Networking / Interview | Good | High | List + inspector pattern works |
| Stats | Thin | Low | P2: duplicates pipeline metrics |

### Candidate new pages

- **Apply readiness** — autofill checklist, ties Settings ↔ workflow
- **Activity timeline** — unified career feed
- **Offer compare** — pathing compensation side-by-side

---

## 7. Settings (12 pages)

### Screens audited

Profile, Academics, Calendar, Assistant, Documents, Finance, Discovery, Career, LMS, Shortcuts, App, Privacy.

### Digestibility

- **Good:** Consistent `AppCard` + `ListRow` + `StatusChip` rhythm; App page metric strip.
- **Weak:** Profile and LMS are single-card stubs; Finance "integrations" card is **empty**; no page explains 12-section IA.

### Polish issues

| ID | Page | Issue | Priority |
|----|------|-------|----------|
| ST-1 | App, Career, Privacy | Raw `<input type="checkbox">` — no Toggle primitive | P1 |
| ST-2 | Finance | Second card body empty | P1 |
| ST-3 | Profile | Stub — prose only, no "Open Identity" button | P1 |
| ST-4 | Academics | Exposes `catalog.selectedProgramIds.v1` in UI copy | P2 |
| ST-5 | Assistant | Web memory only in chat, not settings | P1 |
| ST-6 | — | `SettingsPaneShell` exported but never used | P2 |

### Candidate new pages

- **Integrations hub** — OAuth, APIs, sync status in one scan-friendly page
- **Assistant memory & attachments** — web memory, default attachments
- **Notifications** — due-item prefs (today under App)

---

## 8. Assistant (AI panel + chat)

### Screens audited

AIPanel slide-over (chat), full Assistant module, Syllabus review, Conflict sheet.

### Digestibility

**AIPanel (480px):** **Poor** — runtime chips + metric tiles + empty workspace + attachments + web memory + conversation + quick prompts + input **above the fold**. User must scroll before typing.

**Syllabus review:** Good — course pick → analyze → tabs → conflict sheet. **Not reachable from FAB** (only full module route).

### Polish issues

| ID | Issue | Priority |
|----|-------|----------|
| AS-1 | **No vault/tool citations** on model answers — trust gap for student planner | **P0** |
| AS-2 | Panel overloaded — should be conversation + input only in slide-over | **P0** |
| AS-3 | 15+ nearly identical pending-action confirm banners | P1 |
| AS-4 | Syllabus unreachable from FAB | P1 |
| AS-5 | Role quick prompts look like read-only chips | P2 |

### Reference

Cursor / Notion AI: slim panel, citations on answers, settings for memory in one place.

### Candidate new pages

- **Syllabus inbox** — review queue outside chat
- **Memory manager** — web memory edit/delete
- **Tool audit log** — what assistant changed

---

## 9. Design-system primitives (cross-cutting)

### Consistency matrix

| Pattern | Used well | Inconsistent |
|---------|-----------|--------------|
| `AppCard` + `ListRow` | Settings, Pipeline, Interview | Brag cards, some kanban cards |
| `SegmentedPills` | Pipeline, Growth, Pathing | Openings scope filters |
| `TrailingInspector` | Pipeline, Documents, LMS, Discovery | — |
| `MetricTile` | Finance, Career metrics, Settings App | Stats page underwhelming |
| `PathCScreenFrame` | Degree, Finance dashboard/reports | Most other hubs |
| `EmptyState` | Academics, Finance, Career | Not Profile/LMS/Calendar settings |
| Typography tokens | Some components | **32+ files** with inline `fontSize:` |

### Structural issues

| ID | Issue | Location | Priority |
|----|-------|----------|----------|
| DS-1 | `EmptyState` lives in `Button.tsx` | `Button.tsx` 81–107 | P1 |
| DS-2 | `OverviewWidgetEmpty` vs `EmptyState` — two empty patterns | `OverviewWidgetKit.tsx` | P1 |
| DS-3 | No `Toggle` primitive | Settings, Career | P1 |
| DS-4 | No `InspectorHeader` — repeated `fontSize: 16` blocks | Career views | P1 |
| DS-5 | `SettingsPaneShell` unused | `PathCChrome.tsx` 129 | P2 |

### Recommended additions (in-repo, not MCP)

1. `EmptyState.tsx` — extract from `Button.tsx`
2. `Toggle.tsx` — settings rows
3. `InspectorHeader.tsx` — career/document inspectors
4. `CitationChip` — assistant answers
5. Typography audit — map inline `fontSize` → `text-*` classes

---

## Consolidated findings list (sorted P0 → P2)

### P0 — Ship blockers (trust, dead nav, wrong IA)

| ID | Surface | Finding | File(s) |
|----|---------|---------|---------|
| P0-01 | Home | Week/Goals/Recents sidebar tabs non-functional | `HomeModule.tsx` |
| P0-02 | Home | Today embeds School overview verbatim — not a Home dashboard | `HomeModule.tsx` 86–87 |
| P0-03 | Home | ~16 default widgets; GPA/career/docs/tasks triplicated | `OverviewWidgets.tsx` |
| P0-04 | Home | Hub tiles duplicate pill bar | `HomeModule.tsx` 50–83 |
| P0-05 | Shell | Hub Launcher duplicates pill bar | `HubLauncher.tsx` |
| P0-06 | School | Discover sidebar → Catalog, not Discovery | `SchoolModule.tsx` 12–17 |
| P0-07 | School | Discovery module orphaned from sidebar | `DiscoveryModule.tsx` |
| P0-08 | School | No School Overview in sidebar | `App.tsx` School sidebar |
| P0-09 | Life | Finance "View all" CTAs dead-end to same page | `FinanceDashboardScreen.tsx` |
| P0-10 | Life | Ledger/Goals/Inventory/Receipts unreachable | `FinanceModule.tsx`, `migration.ts` |
| P0-11 | Library | Experiences/Achievements unreachable; Portfolio references them | `ProfileModule.tsx` |
| P0-12 | Career | Pathing: 17 flat inspector tabs | `CareerPathingView.tsx` |
| P0-13 | Assistant | No citations on AI answers | `AssistantModule.tsx` |
| P0-14 | Assistant | AIPanel overloaded — not conversation-first | `AIPanel.tsx`, `AssistantModule.tsx` |

### P1 — High impact polish & digestibility

| ID | Surface | Finding |
|----|---------|---------|
| P1-01 | Shell | Command palette needs group headers; reduce hub duplication |
| P1-02 | Shell | Settings pill selection lie; surface keyboard shortcuts |
| P1-03 | Home | Wire Recents to `recents` state; dedupe widgets; slim header |
| P1-04 | School | Split Catalog browse vs admin; differentiate Plan vs Courses |
| P1-05 | School | LMS inspector action grouping; Discovery fit-prefs UI cleanup |
| P1-06 | Life | Remove double chrome; Budget edit flow; calendar Tasks simplification |
| P1-07 | Library | Add Experiences/Achievements sidebar; category gaps; advisor prep |
| P1-08 | Career | Growth double header; Brag → AppCard; Apply readiness content |
| P1-09 | Settings | Profile actionable; Finance empty card; Toggle primitive; web memory in Assistant settings |
| P1-10 | Assistant | Syllabus in FAB; dedupe pending actions; source chips on all replies |
| P1-11 | Design system | Extract EmptyState; add Toggle, InspectorHeader; tooltip (see MCP audit) |

### P2 — Nice-to-have enhancements

| ID | Surface | Finding |
|----|---------|---------|
| P2-01 | Shell | Logo, pill shortcut badges, sidebar manual collapse |
| P2-02 | Home | Weather deferral; widget rename; GettingStarted invalid widgetId |
| P2-03 | School | Requirement chip overflow; CDS detail pages; transfer grouped views |
| P2-04 | Life | Agenda sidebar; week-at-a-glance; Reports export |
| P2-05 | Library | Bulk ops; portfolio export; course folder metadata |
| P2-06 | Career | Pathing file split; Stats merge; modals split |
| P2-07 | Settings | Integrations hub; hide `.v1` keys in copy |
| P2-08 | Assistant | Conversation history; markdown headings; persisted tool trace |
| P2-09 | Design system | Typography sweep (32 files); consolidate OverviewWidgetEmpty |

---

## Candidate new pages

Pages that would improve IA, digestibility, or close gaps where screens exist in code but aren't reachable.

| Page | Hub | Rationale | Priority |
|------|-----|-----------|----------|
| **Home Today** (rebuilt) | Home | Purpose-built 4–5 card glance; not School borrow | P0 |
| **Home Recents** | Home | Wire existing `recents` state | P0 |
| **Home Week / Goals** | Home | Distinct views or remove tabs | P0 |
| **School Overview** | School | Trimmed academics widget grid on School sidebar | P0 |
| **Schools** (Discovery) | School | Fix Discover→Catalog collision | P0 |
| **Courses** | School | Distinct from Plan semester timeline | P1 |
| **Catalog admin** | Settings | Move sync/scrape off student Discover path | P1 |
| **Ledger** | Life | Full transaction list; fix dashboard CTAs | P0 |
| **Goals** | Life | Separate from budgets | P1 |
| **Life overview** | Life | Schedule + money snapshot | P2 |
| **Experiences** | Library | Portfolio empty states depend on it | P0 |
| **Achievements** | Library | Same | P0 |
| **Advisor prep** | Library | Checklist exists, buried | P1 |
| **Apply readiness** | Career | Close Apply stub; tie Settings | P1 |
| **Activity timeline** | Career | Unified career feed | P2 |
| **Integrations** | Settings | OAuth, APIs, sync in one place | P1 |
| **Assistant memory** | Settings | Web memory config | P1 |
| **Syllabus inbox** | Assistant | Review queue outside chat | P1 |

---

## Suggested implementation phases (for joint review — not started)

**Phase 1 — Trust & navigation (P0):** Fix dead Home tabs; rebuild Home Today; wire Recents; fix School Discover→Discovery; restore unreachable screens (Ledger, Experiences); slim AIPanel; group Pathing tabs.

**Phase 2 — Dedupe & simplify (P1):** Remove duplicate hub nav; dedupe Home/School widgets; double chrome removal; Settings toggles; command palette groups; Career Growth header; Apply readiness.

**Phase 3 — Polish pass (P1–P2):** Design-system extractions (EmptyState, Toggle, InspectorHeader); typography sweep; new pages from candidate list as needed.

---

## Explicitly out of scope for this audit

- MCP component installs (see [MCP_FRONTEND_AUDIT.md](./MCP_FRONTEND_AUDIT.md))
- Backend/API changes (citations require backend `sources[]` — noted as P0 but implementation spans FE+BE)
- Code changes in this pass
