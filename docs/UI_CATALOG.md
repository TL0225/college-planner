# UI Catalog

**Start here for front-end work.** This map lists shared design primitives, shell chrome, and where each module keeps its screens. Feature UI stays in feature packages — do not duplicate primitives listed under [Canonical primitives](#canonical-primitives).

See also: [CODEBASE_INDEX.md](CODEBASE_INDEX.md), [ARCHITECTURE.md](ARCHITECTURE.md), [adr/007-liquid-glass-toolbar-design-system.md](adr/007-liquid-glass-toolbar-design-system.md), [.cursor/rules/custom-native-ui.mdc](../.cursor/rules/custom-native-ui.mdc).

## Design philosophy — Custom Native

Both “stock” and “custom” Mac apps start from the same place: **Apple native UI frameworks** (SwiftUI / AppKit) and **Apple system backends** (persistence, networking, etc.). College chooses the **Custom Native** path:

| Approach | Meaning for College |
| --- | --- |
| **Stock** (avoid) | Default component styling → functional, consistent, System Settings–like |
| **Custom Native** (target) | Native structure + shared custom rendering (vibrant materials, Core Animation / springs, bespoke drawing, physics-like motion) → components that stay accessible and platform-native but look and feel distinctive |

**Reference quality bar** (concepts to borrow, not visual clones): Craft, Dropover, Liqoria, CleanMyMac, GoodLinks, Klack, Things 3, Raycast, Paste, DynamicLake, Portal.

Implementation rule: custom look lives in `CollegeDesignSystem` / documented app design helpers — feature modules compose those primitives.

**Cross-platform (Tauri) — Path C:** Screen-by-screen visual copy of Swift UI into `CollegeDesktop/src/` (React + Tailwind). Shared tokens/primitives under `CollegeDesktop/src/design-system/`; track: [PATH_C_VISUAL_FIDELITY.md](PATH_C_VISUAL_FIDELITY.md). Includes `PathCChrome` (amount hero, inset chart card, kanban lane header, hub tiles), `OverviewWidgetKit`, calendar grids, career timeline, finance charts, and module screen frames.

### Visual parity track (Path C — literal screen copy)

| Pass | Scope | Status |
| --- | --- | --- |
| **Path C Overview kit** | Swift `OverviewWidgetHeader` / row / empty / adaptive grid → React | **Done (v1)** — see [PATH_C_VISUAL_FIDELITY.md](PATH_C_VISUAL_FIDELITY.md) |
| **Path C full checklist (#1–24)** | Finance Chase account, reports, planner, course page, degree audit, hub tiles, `PathCChrome` | **Done (v1)** |
| Shell chrome | Materials-ish chrome gradient, pill/sidebar selection springs, page title type, continuous cards | **Done (v1)** |
| Calendar hero | Month labels, week/day chrome, inspector layout, selected/today states | **Done (v1)** |
| Career hero | Board lanes, StatusChip/LaneDot, PathTimeline spine, inspector chrome | **Done (v1)** |
| Finance surfaces | Dashboard metrics, account/type chips, ledger money rows | **Done (v1)** |
| Academics / Documents / Profile | Overview metrics, degree ProgressBar, vault badges, identity hero | **Done (v1)** |
| Catalog / Discovery | University badges, course code chips, scrape status, school inspector | **Done (v1)** |
| Transfer / LMS | Equivalency map chips, portal kind badges, inspector chrome | **Done (v1)** |
| Assistant / Settings | AI status chips, chat metrics, syllabus rows; Settings metric tiles + inset panels | **Done (v1)** |
| Feature depth track | career_event timeline, Profile Experiences page, Career resume library | **Started (Phase 20)** |
| Feature depth v2 | Finance Goals/Net Worth, Pathing company hub, Calendar color + recurrence | **Done (Phase 21)** |
| Feature depth v3 | Finance Inventory/Receipts/Reports, Career Brag/Networking/Interview, Resume profiles | **Done (Phase 22)** |
| Feature depth v4 | Pathing milestones, Assistant bubbles/markdown, Markdown resume draft | **Done (Phase 23)** |
| Feature depth v5 | Pathing journal + vault docs, ListRow motion, LMS iframe preview | **Done (Phase 24)** |
| Deferred lite | ICS calendar subscribe, LMS WebviewWindow, Typst `.typ` export | **Done (Phase 25)** |
| Deferred complete | Google/Outlook OAuth, OpenAI-compat AI, in-app Typst PDF | **Done (Phase 26)** |
| Frontend catch-up | Documents Finder, Overview widgets, Settings panes, Planner canvas, Discovery modes, Finance charts, Pathing C lite, Resume preview, Assistant roles | **Done (Phase 27)** |
| Optional hardening | Keychain OAuth tokens · bundled ONNX · full Swift Pathing/Resume/MapKit | Optional |

## Layer model

| Layer | Path | Put here when… |
| --- | --- | --- |
| **Design primitives** | `Packages/CollegeDesignSystem/` | Reused across 2+ modules; no domain logic |
| **App chrome helpers** | `College/Core/DesignSystem/` | App-only feedback (hover/press) on top of primitives |
| **Shell / navigation** | `College/App/Shell/`, `College/App/Toolbar/` | Hub launcher, module mounting, College window toolbar |
| **Feature screens** | `Packages/<Module>/UI/` or `College/Features/<Name>/` | One module's views, sheets, inline toolbars |

## Canonical primitives

Use these — do not copy metrics, tokens, or glass helpers into feature folders.

| Concern | Canonical file |
| --- | --- |
| Color / font tokens | `Packages/CollegeDesignSystem/Sources/CollegeDesignSystem/DesignSystem.swift`, `DesignSystem+Tokens.swift`, `Resources/Colors.xcassets` |
| Shared card surface | `Packages/CollegeDesignSystem/Sources/CollegeDesignSystem/AppCard.swift` |
| Page / section headers | `Packages/CollegeDesignSystem/Sources/CollegeDesignSystem/AppPageHeader.swift` (shared); College app re-exports via `College/Core/DesignSystem/AppPageHeader.swift`. Also `UnifiedActionHeader.swift` |
| Primary / secondary buttons | `Packages/CollegeDesignSystem/Sources/CollegeDesignSystem/DesignSystemButtonStyles.swift` (`.designSystemPrimary` / `.designSystemSecondary`, `designSystemFloatingElevation()`) |
| **Sheets** (`CollegeSheetScaffold`, outside-click / Escape dismiss, focus restore) | `Packages/CollegeDesignSystem/Sources/CollegeDesignSystem/Sheets/` — Cancel + primary Design System buttons; `collegeSheetInteractiveDismiss`; app bridge `dismissOnOutsideClickForSheet()` in `College/Core/SheetDismissOnOutsideClick.swift` |
| **Form fields** (`DesignSystemFormField`, `.designSystemFormFieldChrome()`) | `Packages/CollegeDesignSystem/.../Sheets/DesignSystemFormField.swift` — prefer over `.roundedBorder`; Career `PathFormField` wraps these |
| **Unlabeled form input** (`DesignSystemFormFieldInput`) | `Packages/CollegeDesignSystem/.../Sheets/DesignSystemFormField.swift` — bordered field for use under external section titles |
| **Compact date field** (`DesignSystemCompactDateField`) | `Packages/CollegeDesignSystem/.../Sheets/DesignSystemFormField.swift` — text row + calendar popover |
| **Typed date field** (`DesignSystemDateTextField`) | `Packages/CollegeDesignSystem/.../Sheets/DesignSystemFormField.swift` — type a date; `DesignSystemDateParsing` auto-formats on commit (no calendar) |
| **Notes editors** (`DesignSystemNotesEditor`) | `Packages/CollegeDesignSystem/.../Sheets/DesignSystemNotesEditor.swift` — inset text + Enter-continues `-` / `1)` lists; optional formatting bar (`showsFormattingBar`) |
| Filter menus + segmented pills | `Packages/CollegeDesignSystem/Sources/CollegeDesignSystem/DesignSystemFilterMenu.swift`, `DesignSystemSegmentedPills.swift` — Custom Native dropdown/segment chrome (no stock `Picker(.menu)` / `.segmented`). `showsChevron: false` keeps a single system indicator (hides the extra trailing carrot). |
| Inspector sidebar chrome | `Packages/CollegeDesignSystem/Sources/CollegeDesignSystem/InspectorSidebarBackground.swift` |
| **Toolbar metrics** (12pt SF Pro, 44pt hit target, icon labels) | `Packages/CollegeDesignSystem/Sources/CollegeDesignSystem/Toolbar/ToolbarMetrics.swift` |
| **Shared sidebar** (sections + sub-items, icon-only / icon+text, fixed-width rail, elevated selection pill) | `Packages/CollegeDesignSystem/Sources/CollegeDesignSystem/Sidebar/AppSidebar.swift`, `SidebarNavigationModels.swift`, `SidebarMetrics.swift`, `SidebarFooterIconButton.swift`, `AppShellSplitLayout.swift` (`ShellSidebarRail`) |
| **Shell chrome** (flat tint, module pills, interactive hover/press) | `Packages/CollegeDesignSystem/Sources/CollegeDesignSystem/Shell/ShellChromeBackground.swift`, `ModulePillBar.swift`, `DesignSystemInteractiveSurface.swift` |
| **Content pane surface** (flat stage, no inset card box) | `Packages/CollegeDesignSystem/Sources/CollegeDesignSystem/Sidebar/SuperAppContentSurface.swift` |
| Toolbar shared-background helper | `Packages/CollegeDesignSystem/Sources/CollegeDesignSystem/Toolbar/ModuleToolbarSharedBackground.swift` |
| App toolbar hover/press | `College/Core/DesignSystem/ToolbarMetrics.swift` → wraps `toolbarMetricIconButtonStyle()` + `collegeInteractiveSurface(.toolbar)` |
| Interactive hover/press (cards, rows, CTAs) | `College/Core/DesignSystem/CollegeInteractiveSurface.swift` |
| Motion timings | `College/Core/DesignSystem/CollegeMotion.swift` (+ `DesignSystem.Motion` in package — named `durationQuick` / `durationStandard` / `durationSheet` / `durationInspector`, `sheetPresentation` / `inspectorPresentation`, Reduce Motion fallbacks) |
| Sheet / inspector sizing tokens | `DesignSystem.SheetMetrics` / `DesignSystem.InspectorMetrics` in `DesignSystem+Tokens.swift` — prefer over hard-coded frames |
| Named typography scale | `DesignSystem+Tokens.swift` (`pageTitle`, `sectionTitle`, `bodyText`, `chromeControl`, `sidebarRow*`, `display`, `mono`, `serif`, `flexible`); gate: `scripts/check-typography-tokens.sh` |
| Dynamic Type (shell) | `Packages/CollegeDesignSystem/Sources/CollegeDesignSystem/ShellDynamicTypeSupport.swift` (`shellDynamicTypeReadable`) |
| Shared MapKit location picker (`MapLocationPickerSheet`, `MapLocationSearchService`, `ResolvedLocation`, `LocationRecentsStore`) | `Packages/CollegeDesignSystem/Sources/CollegeDesignSystem/Location/` — no `AppContainer` dependency, so Calendar and Finance can both embed it; Calendar keeps its `LocationPickerSheet` name via a thin `College/Core/Location/LocationPickerSheet.swift` wrapper |
| Amount hero (currency-first compose) | `DesignSystemAmountHero` | `Packages/CollegeDesignSystem/Sources/CollegeDesignSystem/Sheets/DesignSystemAmountHero.swift` |
| Notes editor (markdown bar optional) | `DesignSystemNotesEditor` | `Packages/CollegeDesignSystem/Sources/CollegeDesignSystem/Sheets/DesignSystemNotesEditor.swift` |
| Finance sheet sections + stage states | `FinanceSheetSection`, `FinanceStageSurface`, `FinanceHubListRow`, `FinanceConfigureAccountsSection` | `Packages/CollegeFinance/Sources/CollegeFinance/UI/FinancePresentation/` + `UI/FinanceConfigureAccountsSection.swift` |
| Finance inline ledger + inspector | `FinanceInlineLedgerView` | `Packages/CollegeFinance/Sources/CollegeFinance/UI/FinanceInlineLedgerView.swift` |
| Chase-style account summary + balance chart | `FinanceChaseAccountSummary`, `FinanceChaseStyle` | `Packages/CollegeFinance/Sources/CollegeFinance/UI/FinancePresentation/` |
| Finance connections (Coinbase OAuth) | `FinanceConnectionsPanel`, `FinanceConnectCoinbaseSheet` | `Packages/CollegeFinance/Sources/CollegeFinance/UI/FinanceConnectionsUI.swift` |
| Finance location field + place detail | `FinanceLocationField`, `FinancePlaceDetailSheet` | `Packages/CollegeFinance/Sources/CollegeFinance/UI/FinanceForms/` |
| Finance module scaffold (`FinanceModuleScaffold`, `FinanceNavigationState`, `UI/FinancePresentation/`) | `Packages/CollegeFinance/Sources/CollegeFinance/` — title-less `AppPageHeader` + destination bodies; Bank Accounts children in sidebar |
| Sidebar row subtitle (account type tags) | `SidebarNavItem.subtitle` in `Packages/CollegeDesignSystem/.../SidebarNavigationModels.swift`; rendered in `AppSidebar.swift` |
| Sidebar trailing action (e.g. calendar settings gear) | `SidebarNavItem.trailingActionID` / `trailingSystemImage` — sets selection to that id when tapped |
| Timeline primitives (squiggly connector, active/accepted/past/planned bullet states, dashed-future vs solid-history spine, date/spine/content row layout) | `Packages/CollegeDesignSystem/Sources/CollegeDesignSystem/Timeline/PathingTimelinePrimitives.swift` — used by Career Pathing (`CollegeCareer/UI/Pathing/`); respects `accessibilityReduceMotion` |
| Career Pathing resizable trailing inspector | `CareerTrailingInspectorLayout` + `DesignSystem.InspectorMetrics` + shared `@AppStorage("career.inspectorWidth")`; close via `CareerInspectorCloseButton` / `CareerInspectorHeader` |
| Career module scaffold + sheet chrome | `CareerModuleScaffold`, `CareerHeaderActionButton`, `CareerEmptyState`, `CareerSectionHero` in `CollegeCareer/UI/Presentation/`; sheets use app-wide `CollegeSheetScaffold` only (`CollegeDesignSystem/Sheets/`) — no Career/Path sheet wrappers |
| Career Pathing hub rollups (one count semantics) | `CareerPathHubRollup` in `Packages/CollegeCareer/.../Pathing/` — Overview / Pathing cards / Activity share document + event-milestone counts; open roadmap items labeled “open items” not “planned milestones” |
| Career Pathing company hub (org-rooted timeline) | `CareerPathCompanyHub` + `PathCompanyHubInspectorView`; Pathing groups by org via `@AppStorage("career.pathing.groupByOrganization")` (default on) |
| Career Pathing achievement pipeline | `PathAchievementPipelineView` + `CareerPathAchievementPipelineSnapshot` on Overview — Roadmap → Activity → Growth → Accomplishments stages |
| Career Pathing Documents tools | `PathDocumentHub` — search, sort, multi-select bulk unlink/open; optional `siblingEntryIDs` for company-scoped docs |
| Career Pathing Journal | `CareerJournalView` via `CareerSubView.journal` — deep-linked from Overview empty Summary |
| Career Brag Book | `BragBookView` + `CareerBragBookPort` — dated wins with `.eml`/`.msg` import evidence |
| Career organization brand field + Pathing MapKit location | `OrganizationBrandField` / `OrganizationBrandLogoMark` (`CollegeCareer/Branding/`); `PathLocationField` (`CollegeCareer/UI/Pathing/`) reuses `MapLocationPickerSheet` |

### Toolbar naming

| API | Module | Use |
| --- | --- | --- |
| `ToolbarMetrics.*` | `CollegeDesignSystem` | Sizing, fonts, `toolbarIconLabel` |
| `toolbarMetricIconButtonStyle()` | `CollegeDesignSystem` | Package module toolbars (no hover layer) |
| `toolbarIconButtonStyle()` | College app target only | College shell toolbar + interactive feedback |
| `toolbarSegmentButtonStyle()` | `CollegeDesignSystem` | Segmented toolbar controls |
| `moduleToolbarSharedBackgroundHidden()` | `CollegeDesignSystem` | Hides toolbar item shared background on macOS 26+ |

## Shell chrome (persistent super-app)

**Canonical layout** (source of truth for College Overview and every hub module):

```text
┌────────────┬─────────────────────────────────────────────┐
│ traffic    │  ModulePillBar                              │
│ lights     │  College · Finance · Calendar · … · Profile  │
│ (boxed)    │                                             │
├────────────┼─────────────────────────────────────────────┤
│ Overview   │  White content stage (contentSurface)       │
│ Planner    │  Dense module UI (title-less + AppCard)     │
│ Require…   │                                             │
│ Transfer   │                                             │
│            │                                             │
│ ⚙  👤      │                                             │
└────────────┴─────────────────────────────────────────────┘
  gray shellChrome          white contentSurface
```

### Hard rules (do not contradict)

| Rule | Implementation |
| --- | --- |
| Traffic lights boxed by intersecting hairlines | `AppShellSplitLayout` left column rule + header hairline; chrome ignores top safe area |
| Header + sidebar share gray chrome | `shellChromeBackground()` / `DesignSystem.Colors.shellChrome` |
| Content is a white stage | `DesignSystem.Colors.contentSurface` — **true white** (light) / elevated dark (dark), not `controlBackgroundColor`, so it clearly separates from gray `shellChrome` |
| Module switcher in content chrome (not NSToolbar) | `showsChromeHeader: true` + `ModulePillBar` |
| College page rail = Overview · Planner · Requirements · Transfer | `AppShellSidebarSectionsBuilder.collegePages` — no LMS row, no web-shortcut rail |
| Settings / Profile = sidebar footer icons only | `SidebarFooterUtilityGroup` — not in the module pill bar |
| No in-content page titles on Overview | `CollegeInlinePageHeader` → `EmptyView` for overview |
| No window title / Blueprint label | `CollegeAppDelegate.suppressWindowTitle` |
| No system `>>` inspector chrome | custom inspectors / `toolbar(removing: .sidebarToggle)` |

| Surface | Path |
| --- | --- |
| Shell root / sidebar + detail | `College/App/Shell/ShellRootView.swift` |
| Module switcher | `Packages/CollegeDesignSystem/.../Shell/ModulePillBar.swift` (`shell.module.pill.<id>`) |
| Split layout primitive | `Packages/CollegeDesignSystem/.../AppShellSplitLayout.swift` |
| Per-module page sidebar | `College/App/Shell/AppShellSidebar.swift` |
| Detail content surface wrapper | `College/App/Shell/SuperAppShellLayout.swift` |
| Module registry | `College/App/Shell/AppModule.swift` |
| Hub identity gate | `College/App/Shell/HubIdentityCaptureView.swift` |
| Per-module content shells | `College/App/Shell/*ModuleShellView.swift` |
| Sidebar display preference | Settings → Appearance (`sidebar.displayMode.v1`) |
| Selected module storage | `shell.selectedModule.v1` |

### Hub module shells (identical wrap — sidebar owned by `ShellRootView`)

| Module | Shell view |
| --- | --- |
| College | `CollegeModuleRootView` → `ContentView` → `SuperAppShellLayout` |
| Calendar | `CalendarModuleShellView` |
| Career | `CareerModuleShellView` |
| Documents | `DocumentsModuleShellView` (shared `DocumentsStore` from shell root) |
| Assistant | `AssistantModuleShellView` |
| Profile | `ProfileModuleShellView` |
| Finance | `FinanceModuleShellView` → `SuperAppShellLayout` → `FinanceModuleRootView` |

## Module content contract (required for every new page / module)

**Gold standard:** this contract — not Overview’s current layout. Overview is in scope to redesign when it violates the rules below.

Every hub module and College page must compose the same shell surfaces — do not invent a second chrome system (no nested `NavigationSplitView`, no System Settings–style titlebars, no full-bleed stock list chrome).

| Layer | Required primitive | Rule |
| --- | --- | --- |
| Module switch | `ModulePillBar` in content chrome (`AppShellSplitLayout` header) | College + hub apps; Settings stays in sidebar footer |
| Page / section nav | `AppShellSidebar` → `AppSidebar` | Only the active module’s pages; elevated selection pill |
| Detail mount | `SuperAppShellLayout` → `superAppContentSurface()` | Flat content stage — no inset “box” around the whole page |
| Cards / groups | `AppCard` / feature wrappers that use it (e.g. `SettingsCard`) | Grouped content inside the stage, not a second sidebar |
| Page titles | Omit in-content titles (`AppPageHeader(showsTitle: false)` / `EmptyView`) | Shell chrome already identifies place |
| Typography / motion | `DesignSystem.Fonts.*`, `DesignSystem.Motion` / `CollegeMotion` | Named tokens only |
| Density | One global compact rhythm | Content-forward on **every** page — tight `AppPageHeader` / `AppCard` padding, short flat empties, no decorative spacer stacks or oversized section margins. Full-bleed hosts (LMS WKWebView) are the only layout exception. |
| Inspectors | `inspectorSidebarBackground()` | Trailing inspectors only — never a nested content sidebar |

**Settings (in-shell):** `SettingsView` owns its section list inside the content stage (`settings.shellDetail`); the College page rail (Overview / Planner / …) never swaps to Settings sections. Leave Settings via College page rows, the College module pill (re-select), or any other module pill. The standalone macOS `Settings` scene may keep its own split list.

**Ritual:** Before chrome-sensitive PRs, re-check Apple HIG / [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass) in the browser.

## Apple design language alignment (Liquid Glass / HIG)

Consulted: [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass) (2026-07-11), WWDC25 Meet Liquid Glass / design system, WWDC26 AppKit concentricity.

| Apple guidance | College rule |
| --- | --- |
| Liquid Glass = controls & navigation layer above content | Opaque white `contentSurface` for module pages; no full-bleed `bgMain` / `.windowBackground` on the stage |
| Do not overuse glass on content | Cards use `AppCard` / `cardSurface` — never `glassCardBase` as a primary content card fill |
| Standard sheets/popovers/menus pick up system glass | Prefer system presentations; do not paint custom `windowBackground` panels that block Liquid Glass |
| Custom bar fills can fight scroll-edge / system chrome | Module pill bar keeps flat Custom Native + `sharedBackgroundVisibility(.hidden)` (see ADR 013 / `liquid-glass-toolbar.md`) |
| Concentric corners with window/container | Prefer `DesignSystem.Radius.*` + `designSystemConcentricClip()` (`ContainerRelativeShape`) on floating chrome. AppKit `NSViewCornerConfiguration` is not yet Swift-importable on the current SDK — `VisualEffectBlur` uses DS layer radii until then. |
| Reduce Transparency / Reduce Motion | Gate materials and springs via accessibility + `DesignSystem.Motion` / `CollegeReduceMotionGate` |

**Banned on mounted content:** full-bleed `DesignSystem.Colors.bgMain`, raw `.windowBackground` page fills, `glassCardBase` as the main card language.

**Allowed:** `inspectorSidebarBackground()` for trailing inspectors; system Liquid Glass on sheets/menus/floating chrome; true elevation (command palette) via a single DS material/elevation path.

When adding a **new application or page**:

1. Register the module/page in `AppModule` / `AppPage` and sidebar section builder.
2. Mount content under `SuperAppShellLayout` (or College `ContentView` page switch).
3. Put section navigation in `AppShellSidebar`, not inside the feature with a nested split view.
4. Add a row to this catalog’s feature UI table.

## College module in-content chrome (sidebar pages)

| Page | Header / actions |
| --- | --- |
| Overview / Planner / Transfer / LMS | `CollegeInlinePageHeader` in `ContentView+Shell.swift` → `AppPageHeader` |
| Assistant | In-content `AppPageHeader` inside `AIAssistantView` |
| Academics actions | No in-content stats toggle — inspector stays open on Planner/Requirements |
| Settings (in-shell) | `SettingsView` section rail + detail inside content stage (`settings.shellDetail`); College rail stays Overview/Planner/… |
| LMS / shortcuts | `WebNavigationToolbar` inside content header |
| Registry | `ToolbarProviderRegistry.swift` |

Window toolbar is hidden at `ShellRootView`; page titles and actions live in the content stage.

## Feature UI by module

| Module | Primary UI path | Package |
| --- | --- | --- |
| Academics | `Packages/CollegeWorkspace/UI/Academics/` | `CollegeWorkspace` |
| Degree / Courses | `Packages/CollegeWorkspace/UI/Degree/`, `CourseDashboardScreen+*.swift` | `CollegeWorkspace` |
| Calendar | `Packages/CollegeCalendar/UI/`, `Views/` | `CollegeCalendar` |
| Career | `Packages/CollegeCareer/UI/` (+ Brag Book; sidebar: Board · Openings · Pathing · Brag Book · Resumes · Networking · Interview; chrome: `CareerModuleScaffold` + `AppPageHeader`) | `CollegeCareer` |
| Documents | `Packages/CollegeDocuments/UI/` | `CollegeDocuments` |
| Finance | `Packages/CollegeFinance/Sources/CollegeFinance/UI/` (+ Settings → `SettingsFinancePanel` Coinbase view-only connect; sidebar: Dashboard · **Bank Accounts** (account children) · Budget · **Net Worth** · Goals · Inventory · Receipts · Reports; Dashboard **Configure Accounts** is the CSV/manual account shop; chrome: `FinanceModuleScaffold` + `AppPageHeader`; hubs are inset lists + sheets) | `CollegeFinance` |
| Transfer | `Packages/CollegeTransfer/UI/` | `CollegeTransfer` |
| Discovery | `Packages/CollegeDiscovery/Sources/CollegeDiscovery/UI/` — fixed ~280pt school list + detail (no nested `NavigationSplitView` / sidebar toggle), underline profile tabs, coverage pills, filled metric grid cards, bordered “Known for” card; list rows show Net/Adm/Grad only | `CollegeDiscovery` |
| LMS | `Packages/CollegeLMS/UI/` | `CollegeLMS` |
| SyllabusAI | `Packages/CollegeSyllabusAI/UI/` | `CollegeSyllabusAI` |
| Assistant | `College/Features/Assistant/` | — (app-hosted) |
| Profile | `College/Features/Profile/` | — |
| Overview | `College/Features/Overview/` | — |
| Resume | `College/Features/Resume/` | — |
| Settings | `College/Features/Settings/SettingsView.swift` | In-shell College page (+ optional macOS Settings scene) |
| Onboarding | `College/App/OnboardingRootView*.swift` | — |

## Adding new UI

1. **Shared control or token?** → `CollegeDesignSystem` (+ document in this file).
2. **One module screen?** → that module's `UI/` folder; import `CollegeDesignSystem`.
3. **Shell / hub chrome?** → `College/App/Shell/` or `College/App/Toolbar/`.
4. **Never** duplicate `ToolbarMetrics`, catalog regex/normalization, or ingest signatures — see [CODEBASE_INDEX.md](CODEBASE_INDEX.md#canonical-utilities-do-not-duplicate).

## Planned migrations (not done yet)

These remain in `College/Core/DesignSystem/` until a later pass proves they are stable enough to move into `CollegeDesignSystem`:

- `CollegeInteractiveSurface.swift`, `CollegeMotion.swift`
- `AutoGrowingTextEditor.swift`, `DashboardHints.swift`

**Visual consistency gates:** `scripts/check-content-surface.sh`, `scripts/check-radius-tokens.sh`, plus existing `check-typography-tokens.sh` / `check-motion-tokens.sh`.

When moving, update this catalog and run `python3 scripts/audit-runtime-codebase.py`.
