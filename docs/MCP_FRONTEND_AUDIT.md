# MCP-Sourced Front-End Audit

Audit-only pass. **No source files were changed while producing this document.**

## Method & servers used

Three live MCP servers were queried per surface, using surface-relevant search terms, and results were cross-referenced against the actual `CollegeDesktop/src` codebase (not assumptions):

- **Magic UI** (`user-@magicuidesign/mcp`) — `searchRegistryItems` / `getRegistryItem`. Motion/effects primitives (beams, tickers, grids, file trees, typing animation).
- **21st.dev** (`user-21st`) — `search` / `get_component`. Community React/shadcn components (dashboards, kanban boards, chat bubbles, profile cards).
- **shadcn/ui** (`user-shadcn`) — `search_items_in_registries`. Canonical shadcn primitives and blocks (`command`, `sidebar`, `calendar`, `chart-*`, `dialog`, `sonner`, `tooltip`, etc.).

**Key finding up front:** CollegeDesktop already ships a mature, bespoke design system (`src/design-system/*`) — `AppCard`, `ModalSheet`, `CommandPalette`, `MonthGrid`/`WeekGrid`/`DayTimeline`, `KanbanLaneHeader`, `EmptyState`, `MetricTile`/`SegmentedPills`, `PathCChrome` primitives, a `MotionProvider` + `useReduceMotion` hook, and semantic typography tokens (`--type-*`, `text-page-title`, etc.). Most MCP-catalog components are generic SaaS/marketing-site patterns that do **not** match this app's tight, native-feeling, Swift-parity visual language. Consequently, the majority of matches below are recorded as **reference-only / do-not-install**, and the audit instead surfaces small, targeted gaps — the same way the existing hand-built primitives were designed. Wholesale swaps to community components would be a regression in fidelity and are explicitly rejected.

## Guiding principle: super-app simplification (applies to every surface below)

CollegeDesktop's product intent is a **super-app**: several purpose-built sub-apps (School, Career, Life, Library, Assistant) living inside one shell, cross-linked so they "talk to each other" (e.g. the Assistant can create a calendar event, a career task can surface in Life's task list, documents can attach to a course). That intent has two direct consequences that should override any generic UI-kit suggestion in this audit:

1. **Every screen must earn its place with content that is genuinely specific to its hub** — not a reused sub-page from a different hub wearing a different header. Cross-hub *linking* (deep links, shared data, "open in Life") is exactly the super-app behavior wanted; cross-hub *content duplication* (rendering another hub's whole page verbatim) is the opposite of it and reads as unfinished.
2. **Every interactive element must do something distinct**, or it should not exist. A super-app with 5 hubs and dozens of pages is only usable if navigation is trustworthy — a tab, tile, or link that doesn't change the screen erodes trust in the entire nav model, not just that one control.

The Home hub audit below (§2) is a confirmed, concrete case of both problems. The same two checks — *"is this hub's content actually its own?"* and *"does every visible control do something different from its siblings?"* — should be applied when auditing the remaining hubs; that follow-up pass has not been run yet and is tracked as an open item at the end of this document.

## Summary table

| # | Surface | Bespoke coverage | Real gaps found | Top recommendation |
|---|---------|-------------------|------------------|---------------------|
| 1 | Shell chrome & navigation | Strong (`CommandPalette`, `AppSidebar`, `ModulePillBar`) | None functional; minor a11y | Keep as-is |
| 2 | Home hub & overview widgets | **Weak — not a real Home dashboard** | 3 of 4 sidebar tabs are non-functional; "Today" reuses School's Academics Overview verbatim; duplicate nav row; same GPA/credits shown 3×; inline `fontSize` | **Rebuild as a purpose-built Home surface** (P0, in-repo — not an MCP gap) |
| 3 | School hub (Academics/Catalog/Discovery/LMS) | Strong, custom | Inline `fontSize`; no styled `Tooltip` | Add `Tooltip` primitive (shadcn) |
| 4 | Life hub (Calendar + Finance) | Very strong, fully custom calendar grids | None functional | Keep as-is |
| 5 | Library hub (Documents + Profile) | Adequate | Documents list could use tree affordance polish | Optional Magic UI `file-tree` reference only |
| 6 | Career hub (Pipeline/Pathing/Resume) | Strong — bespoke Kanban already exists | None functional | Keep as-is |
| 7 | Settings | Adequate | No styled `Switch`; native `<input type="checkbox">` | Add `Switch` primitive (shadcn) |
| 8 | Assistant (AI panel + chat) | Adequate, custom markdown renderer | No dedicated message-bubble component | Optional: extract `AssistantMessage` component (in-repo, not installed) |
| 9 | Design-system primitives (cross-cutting) | Strong | Missing `Tooltip`, `Switch`; 40+ files with inline `fontSize` | Add 2 shadcn primitives; token sweep |

## 1. Shell chrome & navigation

**Current state:** `App.tsx` composes `PlatformProvider` → `MotionProvider` → `PageTransition` + `CommandPalette` + `AIPanel` + `ModulePillBar`. `CommandPalette.tsx`, `AppSidebar.tsx`, `ModulePillBar.tsx` are already bespoke, motion-aware (`useReduceMotion`), and token-driven.

**Magic UI:** `dock` (`registry:ui`, macOS dock) — reference only, not applicable; app uses a pill bar, not a dock.

**21st:** 5 command-palette variants found (Raycast-style, fuzzy-search, omni-palette) — all reference-only; the existing `CommandPalette.tsx` already implements keyboard nav + fuzzy-ish filtering natively and is themed to match the shell chrome exactly. Installing a community one would break visual parity.

**shadcn:** `command` (`registry:ui`), `sidebar` + 31 sidebar block variants (`sidebar-01`…`sidebar-12`) — reference-only; `AppSidebar.tsx` is purpose-built for the 5-hub IA and already denser/simpler than shadcn's generic sidebar block.

**Recommended changes:**

| File | Change | Source | Priority |
|------|--------|--------|----------|
| — | No changes needed | — | — |

## 2. Home hub & overview widgets

**Current state — this hub fails the super-app simplification test on both counts (see guiding principle above):**

**Finding A — 3 of 4 sidebar tabs are non-functional.** `App.tsx` declares the Home sidebar with four items (`today`, `week`, `goals`, `recents`), but `HomeModule.tsx` only uses `page` as a gate check, then renders one hardcoded path regardless of which tab is selected:

```25:30:CollegeDesktop/src/modules/home/HomeModule.tsx
if (page !== "today" && page !== "week" && page !== "goals" && page !== "recents") {
    return (
      <div className="flex h-full items-center justify-center p-6 text-body text-[var(--color-text-light)]">
        Select a page from the sidebar.
      </div>
    );
  }
```

There is no branch on `page` after this — the header is a hardcoded `<h1>Today</h1>` and the body is the same widget grid no matter which tab is active. Clicking Week, Goals, or Recents changes only the sidebar highlight; the content and title never change. This is the exact behavior flagged during manual testing ("the tabs although renamed, don't do anything different").

**Finding B — "Today" is not Home-specific content; it's School's Academics Overview, reused verbatim.** `HomeModule.tsx` embeds:

```85:87:CollegeDesktop/src/modules/home/HomeModule.tsx
      <div className="min-h-0 flex-1">
        <AcademicsModule page="academics" hideChrome />
      </div>
```

`AcademicsModule` with `page="academics"` sets `view = "overview"`, which renders `OverviewWidgetGrid` from `OverviewWidgets.tsx` — the same widget grid `docs/UI_CATALOG.md` documents as "School Overview" and the same component the School hub itself uses. Home has no dashboard of its own; it borrows another hub's full page. This directly violates the "every hub's content must be its own" check and is the root cause of the "doesn't look polished" impression — nothing on the page was designed for Home specifically.

**Finding C — duplicate navigation.** `HomeModule.tsx` renders four `HubModuleTile`s (School/Life/Career/Library) that navigate to the exact same destinations the top `ModulePillBar` already exposes — a second nav row before any unique content appears.

**Finding D — the same two numbers (completed credits, cumulative GPA) are rendered three separate times** on one screen: the "Academic Calendar" widget (raw numbers), the "Academic Journey" widget (as a ring + GPA line), and the standalone "GPA" widget. Combined with 12+ other interchangeable widgets (weather, net worth, saved schools, advisor prep, career pipeline, documents…), the page reads as an un-curated settings-style widget picker rather than a focused "Today" glance.

**Finding E — label collision.** The "Week Ahead" widget's "Open week view →" link navigates to the Life hub's calendar week view (a real feature). The Home sidebar's own "Week" tab is a different, non-functional destination with the same name.

**Finding F — "Recents" is disconnected wiring, not a missing feature.** `App.tsx` already maintains `recents: ShellRecent[]` (`{module, page, title}`), appending an entry on every navigation — the data exists and is populated, it is simply never rendered by the "Recents" tab.

`OverviewWidgets.tsx` additionally has 9 occurrences of inline `fontSize:` styles instead of typography tokens (pre-existing minor finding, retained below).

**Magic UI:** `bento-grid`, `animated-grid-pattern`, `flickering-grid` — reference-only decorative backgrounds; not appropriate for a productivity app's content surfaces (would add visual noise), and would not address any of Findings A–F above.

**21st:** "Stats Widget" (id 4157), "Dashboard Overview" (id 8371), "Advanced Stats" (id 19070) — reference-only; `MetricTile`/`OverviewWidgetCard` already cover this exact need with theme-correct tokens. None of these fix the structural problem — the issue is not a missing widget component, it's that Home has no distinct dashboard and 3 dead tabs.

**shadcn:** `dashboard-01` block, `card` — reference-only, same reasoning.

**Recommended changes:**

| File | Change | Source | Priority |
|------|--------|--------|----------|
| `src/modules/home/HomeModule.tsx` | Branch real content per `page` (`today`/`week`/`goals`/`recents`) instead of one hardcoded render path; update `<h1>` to match the active tab | In-repo, no MCP install — structural fix | **P0** |
| `src/modules/home/HomeModule.tsx` | Build a Home-specific "Today" view (a small, curated glance: e.g. today's schedule + top 3 deadlines + quick actions) instead of embedding `<AcademicsModule page="academics" hideChrome />` | In-repo, no MCP install — structural fix | **P0** |
| `src/modules/home/HomeModule.tsx` | Wire the "Recents" tab to the existing `recents` state already tracked in `App.tsx` (pass it down, render as a list) | In-repo, no MCP install — data already exists | **P0** |
| `src/modules/home/HomeModule.tsx` | Define real "Week" and "Goals" content for Home (distinct from Life's week view and any future goals feature), or remove those tabs until content exists | In-repo, product decision needed | **P0** |
| `src/modules/home/HomeModule.tsx` | Remove the duplicate School/Life/Career/Library `HubModuleTile` row (already covered by `ModulePillBar`) | In-repo, no MCP install | P1 |
| `src/modules/academics/OverviewWidgets.tsx` | Dedupe GPA/credits shown across "Academic Calendar," "Academic Journey," and "GPA" widgets into one source of truth; curate the widget count for a glanceable "Today" (this may live on Home, School Overview, or both, but should not repeat) | In-repo, no MCP install | P1 |
| `src/modules/academics/OverviewWidgets.tsx` | Replace 9 inline `fontSize:` styles with existing typography classes/tokens (`text-meta`, `text-section-title`, etc.) | Keep as-is (in-repo tokens, no MCP install) | P2 |

## 3. School hub (Academics/Catalog/Discovery/Transfer/LMS)

**Current state:** `CourseDashboard.tsx`, `CourseDashboardKit.tsx`, `ProgramBrowser.tsx`, `PlannerCanvas.tsx`, `DegreeRequirementsScreen.tsx`, `CatalogModule.tsx`, `DiscoveryModule.tsx`/`DiscoveryCompareTable.tsx`, `LmsModule.tsx`, `TransferModule.tsx` — all custom, use `AppCard`/`FilterMenu`/`ContentToolbar`. Multiple files (`CourseDashboard.tsx`×2, `CourseDashboardKit.tsx`×3, `CareerPathingView.tsx`×3, etc.) use inline `fontSize:`. No styled tooltip exists anywhere in the design system — hover hints rely on the native `title=` attribute (seen in `AppSidebar.tsx`, `WeekGrid.tsx`, `UserMenu.tsx`, `AIPanel.tsx`, `InteractiveSurface.tsx`), which is inconsistent, undelayed, and unstyled versus the rest of the polished UI.

**Magic UI:** `animated-circular-progress-bar` — potential fit for degree-completion % in `DegreeRequirementsScreen.tsx`, but `ProgressBar` and `CreditRing` (`OverviewWidgetKit.tsx`) already provide this exact pattern in-repo. Reference-only.

**21st:** "Comparison Table" (id 7469) — reference-only; `DiscoveryCompareTable.tsx` is already a bespoke, theme-matched compare table for school comparison. Circular progress variants (ids 1727, 6187, 22095) — reference-only, redundant with `CreditRing`.

**shadcn:** `tooltip` (`registry:ui`) — **genuine gap**, install command: `npx shadcn@latest add tooltip` (then re-skin to design tokens, don't use default shadcn styling wholesale). `combobox` (`registry:ui`) — reference-only; catalog/course search already uses `FilterMenu` + free-text inputs, which is arguably better suited to the dense finder-style UI than a shadcn combobox popover. `data-table-demo` — reference-only; existing list views (`ListRow`) are lighter-weight than TanStack-table-based shadcn data tables and better match the app's density.

**Recommended changes:**

| File | Change | Source | Priority |
|------|--------|--------|----------|
| `src/design-system/components/` (new `Tooltip.tsx`) | Add a themed tooltip primitive to replace native `title=` attributes | shadcn `tooltip` (`npx shadcn@latest add tooltip`, then re-theme) | P1 |
| `src/design-system/components/AppSidebar.tsx`, `WeekGrid.tsx`, `UserMenu.tsx`, `AIPanel.tsx`, `InteractiveSurface.tsx` | Swap native `title=` for the new `Tooltip` primitive once added | Follows from above | P2 |
| `src/modules/academics/CourseDashboard.tsx`, `CourseDashboardKit.tsx`, `ProgramBrowser.tsx` (and similar) | Replace inline `fontSize:` with typography tokens | Keep as-is (in-repo), no MCP install | P2 |

## 4. Life hub (Calendar + Finance)

**Current state:** `CalendarModule.tsx` (1712 lines) implements `MonthGrid`, `WeekGrid`, `DayTimeline`, ICS sync, geocoding, and its own event-color system — this is a genuinely deep, custom calendar implementation, well beyond what any MCP component offers. `FinanceModule.tsx`, `FinanceDashboardScreen.tsx`, `FinanceCharts.tsx`, `FinanceAccountDetailScreen.tsx`, `FinanceReportsScreen.tsx` cover budgets/accounts/reports with bespoke charts.

**shadcn:** `calendar` (`registry:ui`, a single-month date-picker primitive) — **not a fit**; it's a date-picker, not a scheduling calendar with month/week/day views, ICS sync, or location mapping. `sidebar-12` ("sidebar with a calendar") — reference-only. 71 `chart-*` blocks (Recharts-based bar/line/pie/area) — reference-only; `FinanceCharts.tsx` is custom and already theme-matched; swapping to shadcn's Recharts wrapper would add a new charting dependency for no visual gain.

**21st:** "Financial Score Cards" (id 5409, animated half-circle progress + staggered entrance), "Weekly Expense Card" (id 7715, animated bubble chart), "Wallet Card" variants — all reference-only; `FinanceDashboardScreen.tsx` already has its own metric tiles.

**Magic UI:** `animated-list` — reference-only; not a fit for calendar's fixed-grid layouts.

**Recommended changes:**

| File | Change | Source | Priority |
|------|--------|--------|----------|
| — | No changes needed | — | — |

## 5. Library hub (Documents + Profile)

**Current state:** `DocumentsModule.tsx` and `LibraryModule.tsx` render a flat/foldered document list using `ListRow`/`AppCard`. `ProfileModule.tsx` has 2 inline `fontSize:` occurrences.

**Magic UI:** `file-tree` (`registry:ui`) — install: `npx shadcn@latest add "https://magicui.design/r/file-tree.json"`. Legitimate reference for a future nested-folder view if Documents grows beyond a flat list, but current data model/UI is flat — **not needed now**.

**21st:** File-tree/file-browser variants (ids 19150, 24877, 15593, 3940, 23573) — reference-only, same reasoning. Profile-card variants (ids 4314, 9890, 2593, 2581, 8563) — reference-only; `ProfileModule.tsx` already renders identity info in the app's own `AppCard` styling; swapping to a generic "profile card" would look like a bolted-on widget rather than a native section.

**shadcn:** `avatar` (`registry:ui`) — **possible small gap** if `ProfileModule.tsx` currently renders initials/photo manually rather than via a shared avatar primitive (verify at implementation time).

**Recommended changes:**

| File | Change | Source | Priority |
|------|--------|--------|----------|
| `src/modules/profile/ProfileModule.tsx` | Replace 2 inline `fontSize:` styles with typography tokens | Keep as-is, no MCP install | P2 |
| `src/design-system/components/` | Consider a shared `Avatar` primitive if avatar rendering is currently duplicated ad hoc | shadcn `avatar` (`npx shadcn@latest add avatar`) | P2 (verify need first) |

## 6. Career hub (Pipeline/Pathing/Resume/Growth)

**Current state:** `CareerPipelineView.tsx` already implements a full drag-and-drop Kanban board using in-repo `KanbanLaneHeader`, `LaneDot`, `StatusChip`, and native `DragEvent` handlers across `interested/applied/interviewing/offer/rejected/accepted` lanes — this is a complete, working, theme-correct Kanban, not a gap. `PathingStoriesPanel.tsx`, `PathingGoalsPanel.tsx`, `PathingResumePanel.tsx`, `ResumeLiveBuilder.tsx`, `CareerInterviewTimeline.tsx` round out the hub.

**21st:** 5 Kanban-board components (ids 24340, 2316, 9627, 4224, 4901) — **explicitly rejected**; the existing bespoke pipeline view is functionally complete and visually integrated. Installing a community Kanban would duplicate functionality and require re-theming from scratch for zero net gain. "Timeline-02" (id 5534), "ProjectPulseTracker" (id 2630), "Impact Experience" (id 18893) — reference-only; `CareerInterviewTimeline.tsx`/`PathTimeline` already exist.

**shadcn:** No `kanban` items in the registry (confirmed via search — zero results).

**Magic UI:** `animated-beam` — reference-only; not applicable to a linear pathing timeline.

**Recommended changes:**

| File | Change | Source | Priority |
|------|--------|--------|----------|
| — | No changes needed | — | — |

## 7. Settings

**Current state:** `SettingsModule.tsx` routes to 12 page components (`SettingsProfilePage`, `SettingsAcademicsPage`, …). `SettingsAppPage.tsx` and `SettingsCareerPage.tsx` use raw `<input type="checkbox">` for boolean toggles rather than a themed switch — this is a real, visible inconsistency versus the rest of the polished UI (buttons, pills, and fields are all custom-styled).

**shadcn:** `switch` (`registry:ui`) — **genuine gap**, install: `npx shadcn@latest add switch` (then re-skin to `--color-primary` / chrome tokens). `tabs` (`registry:ui`) — reference-only; settings uses a sidebar-style page list, not tabs, and that pattern is fine as-is.

**21st / Magic UI:** No settings-specific matches beyond generic "dashboard configuration" (21st id 8693, reference-only — different visual language) and `animated-theme-toggler` (Magic UI, install: `npx shadcn@latest add "https://magicui.design/r/animated-theme-toggler-demo.json"`) — a nice-to-have for the light/dark toggle in `SettingsAppPage.tsx`, but purely optional polish, not a correctness gap.

**Recommended changes:**

| File | Change | Source | Priority |
|------|--------|--------|----------|
| `src/design-system/components/` (new `Switch.tsx`) | Add a themed switch primitive | shadcn `switch` (`npx shadcn@latest add switch`, re-theme) | P1 |
| `src/modules/settings/pages/SettingsAppPage.tsx`, `SettingsCareerPage.tsx` | Replace `<input type="checkbox">` toggles with the new `Switch` primitive | Follows from above | P1 |
| `src/modules/settings/pages/SettingsAppPage.tsx` | Optional: animate the theme toggle | Magic UI `animated-theme-toggler` (reference, re-theme required) | P2 (optional) |

## 8. Assistant (AI panel + chat)

**Current state:** `AssistantModule.tsx` (1500+ lines) implements a full agent chat loop — streaming chunks, tool-call status labels (`TOOL_LABELS`), pending-action confirmation cards, and a custom `SimpleMarkdown` renderer. Message rendering appears to be done inline rather than via an extracted, reusable message component.

**21st:** "AI Message Bubble" (id 20125, streaming cursor + copy-on-hover), "AI Message" (id 23819, explicitly "respects prefers-reduced-motion" — matches this app's own motion philosophy), "Chat Messages" (id 20129) — all reference-only for visual style; the actual code should not be installed wholesale since it doesn't know about `PendingAction`, `AgentRole`, or `TOOL_LABELS`, but the interaction pattern (hover-reveal actions, streaming cursor) is a good **structural reference** for extracting the message-rendering logic into its own component.

**Magic UI:** `typing-animation` — reference-only; the assistant already shows tool-status labels while working, which is arguably clearer than a generic typing dots animation.

**shadcn:** No dedicated chat primitives (searches for "chat" only surfaced unrelated `chart-*` blocks).

**Recommended changes:**

| File | Change | Source | Priority |
|------|--------|--------|----------|
| `src/modules/assistant/AssistantModule.tsx` | Consider extracting message rendering into a dedicated `AssistantMessage` component (in-repo refactor, structural reference only from 21st id 23819's hover-reveal action pattern) | Keep as-is / in-repo refactor, no install | P2 (optional refactor, not a bug) |

## 9. Design-system primitives (cross-cutting)

**Current state:** `src/design-system/index.ts` exports a broad, coherent set: `Button`, `FormField`, `EmptyState`, `ModulePillBar`, `AppSidebar`, `AppCard`, `ModalSheet`, `CommandPalette`, `ToastHost`, `InteractiveSurface`, `StatusChip`/`LaneDot`, `PathTimeline`, `ProgressBar`, `TrailingInspector`, `ShellSplitLayout`, `MetricTile`/`SegmentedPills`/`ListRow`, `MonthGrid`/`WeekGrid`/`DayTimeline`, `OverviewWidgetKit` (incl. `CreditRing`), `PathCChrome` primitives (incl. `KanbanLaneHeader`, `HubModuleTile`), `ContentToolbar`, `FilterMenu`, `DateField`, `NotesEditor`, `UserMenu`, `AIPanel`, `ScrollArea`, plus `MotionProvider`/`useReduceMotion`/`PageTransition`/`StaggeredList`. **Missing**: `Tooltip`, `Switch`/`Toggle`, and a styled `Dialog`/`AlertDialog` (currently `ModalSheet` covers general modals, but destructive confirmations go through `confirmDelete` in `src/lib/confirm.ts`, not a themed dialog — worth a quick check but out of scope here since it wasn't flagged as broken).

Across the codebase, inline `fontSize:` styles appear in **32 files**, most heavily in `OverviewWidgets.tsx` (9), `MonthGrid.tsx`/`CourseDashboardKit.tsx`/`CareerPathingView.tsx`/`FinanceAccountDetailScreen.tsx` (3 each). None of these are MCP-sourceable fixes — they're a token-adoption cleanup using the app's *own* `--type-*` variables already defined in `styles.css`.

**shadcn:** `tooltip`, `switch` — both genuine, small, additive primitives (see #3 and #7 above; listed once each in the consolidated log below, not duplicated).

**Magic UI:** `border-beam`, `ripple`, `shimmer-button`-style effects — reference-only; the app's `Button.tsx` already has hover/tap motion via `useReduceMotion`, and decorative beams/ripples don't match the utilitarian, native-app aesthetic.

**21st:** "Empty State" variants (ids 21518, 19369, 19377, 22301, 19745) — reference-only; `EmptyState` (`Button.tsx:81`) already exists in-repo and is used consistently (confirmed via search) across `AssistantModule.tsx`, `CareerPipelineView.tsx`, `CalendarModule.tsx`, `AcademicsModule.tsx`, etc. No gap here.

**Recommended changes:**

| File | Change | Source | Priority |
|------|--------|--------|----------|
| `src/design-system/components/Tooltip.tsx` (new) | Add themed tooltip primitive | shadcn `tooltip` | P1 |
| `src/design-system/components/Switch.tsx` (new) | Add themed switch primitive | shadcn `switch` | P1 |
| 32 files with inline `fontSize:` | Sweep to typography tokens (`text-*` classes / `--type-*` vars) | In-repo, no MCP install | P2 |

## Consolidated change log (all items, sorted by priority)

| Priority | File(s) | Change | Source / install |
|----------|---------|--------|-------------------|
| **P0** | `src/modules/home/HomeModule.tsx` | Branch real, distinct content per sidebar tab (`today`/`week`/`goals`/`recents`) — currently all four render the same hardcoded output | In-repo, no MCP install — structural fix |
| **P0** | `src/modules/home/HomeModule.tsx` | Replace the embedded `<AcademicsModule page="academics" hideChrome />` (School's Overview page) with a Home-specific "Today" view | In-repo, no MCP install — structural fix |
| **P0** | `src/modules/home/HomeModule.tsx`, `App.tsx` | Wire "Recents" tab to the already-tracked `recents: ShellRecent[]` state | In-repo, no MCP install — data already exists |
| **P0** | `src/modules/home/HomeModule.tsx` | Define real "Week" / "Goals" content for Home, or remove those tabs until designed | In-repo — product decision needed |
| P1 | `src/modules/home/HomeModule.tsx` | Remove duplicate School/Life/Career/Library `HubModuleTile` row (redundant with `ModulePillBar`) | In-repo, no MCP install |
| P1 | `src/modules/academics/OverviewWidgets.tsx` | Dedupe GPA/credits repeated across 3 widgets; curate widget count for a glanceable view | In-repo, no MCP install |
| P1 | `src/design-system/components/Tooltip.tsx` (new) | Add themed tooltip primitive, replace native `title=` in `AppSidebar.tsx`, `WeekGrid.tsx`, `UserMenu.tsx`, `AIPanel.tsx`, `InteractiveSurface.tsx` | shadcn `tooltip` — `npx shadcn@latest add tooltip` (re-theme to design tokens) |
| P1 | `src/design-system/components/Switch.tsx` (new) | Add themed switch primitive, replace `<input type="checkbox">` in `SettingsAppPage.tsx`, `SettingsCareerPage.tsx` | shadcn `switch` — `npx shadcn@latest add switch` (re-theme) |
| P2 | `src/modules/academics/OverviewWidgets.tsx` | Replace 9 inline `fontSize:` styles with typography tokens | In-repo, no install |
| P2 | `src/modules/academics/CourseDashboard.tsx`, `CourseDashboardKit.tsx`, `ProgramBrowser.tsx`, `CareerPathingView.tsx`, `FinanceAccountDetailScreen.tsx`, `MonthGrid.tsx`, and ~26 other files | Sweep remaining inline `fontSize:` styles to typography tokens | In-repo, no install |
| P2 | `src/modules/profile/ProfileModule.tsx` | Replace 2 inline `fontSize:` styles with typography tokens | In-repo, no install |
| P2 | `src/design-system/components/` | Consider shared `Avatar` primitive if avatar markup is duplicated (verify first) | shadcn `avatar` — `npx shadcn@latest add avatar` |
| P2 (optional) | `src/modules/assistant/AssistantModule.tsx` | Optionally extract message rendering into `AssistantMessage` component | In-repo refactor; structural reference only from 21st id 23819 |
| P2 (optional) | `src/modules/settings/pages/SettingsAppPage.tsx` | Optionally animate theme toggle | Magic UI `animated-theme-toggler` (reference, re-theme required) |
| Skip | — | No changes for Shell chrome, Calendar/Finance, Career Kanban — all already bespoke and complete | — |

## Explicitly out-of-scope / rejected suggestions (with reason)

| Suggestion | Source | Reason rejected |
|---|---|---|
| Community Kanban board (5 variants) | 21st | Existing `CareerPipelineView.tsx` is a complete, working, theme-matched Kanban; reinstalling would duplicate logic and require full re-theming for no gain. |
| Community command palettes (5 variants) | 21st | `CommandPalette.tsx` is already bespoke, motion-aware, and chrome-themed; swap would break visual parity. |
| shadcn `sidebar` + 31 block variants | shadcn | `AppSidebar.tsx` is purpose-built for the 5-hub IA; generic sidebar blocks are denser/heavier and don't match. |
| shadcn `calendar` (date-picker) | shadcn | Not a fit — it's a single-month date picker, not a scheduling calendar; `MonthGrid`/`WeekGrid`/`DayTimeline` already provide month/week/day views with ICS sync. |
| 71 shadcn `chart-*` Recharts blocks | shadcn | Would add a new charting dependency (Recharts) purely to reproduce what `FinanceCharts.tsx` already does with a lighter, theme-matched custom implementation. |
| Bento grids / animated grid patterns / flickering grids / border beams / ripples | Magic UI | Decorative marketing-site effects; inconsistent with the app's utilitarian, native-desktop aesthetic. |
| Community "Empty State" components (5 variants) | 21st | `EmptyState` already exists in-repo (`Button.tsx:81`) and is used consistently across the app. |
| Community profile cards (5 variants) | 21st | `ProfileModule.tsx` already renders identity data inside the app's own `AppCard` styling; a generic "profile card" would look bolted-on. |
| Magic UI `file-tree` | Magic UI | Documents/Library currently use a flat list, not a nested folder tree; installing now would be building for a data model that doesn't exist yet. |
| Magic UI `typing-animation` | Magic UI | Assistant already surfaces tool-status labels (`TOOL_LABELS`) while working, which communicates state more precisely than a generic typing-dots animation. |

## Open follow-up: cross-hub simplification pass

The Home hub findings in §2 confirmed two concrete failure modes — non-functional nav controls, and a hub rendering another hub's content wholesale instead of its own. Per the guiding principle above, **the remaining hubs (School, Life, Library, Career, Settings, Assistant) have not yet been checked for the same two failure modes** and should be, as a dedicated pass:

1. For every sidebar/tab item in every hub, confirm it renders content distinct from its siblings (no dead tabs).
2. For every hub's landing/overview page, confirm the content was designed for that hub and isn't a reused sub-page from elsewhere.
3. Flag any widget/data duplication within a single screen (the GPA/credits triple-render in §2 is the confirmed example; other hubs have not been checked for the same pattern).

This is scoped as follow-up work, not yet executed, so it is not itemized in the consolidated change log above.
