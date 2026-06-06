# Toolbar Development Guidelines

Rules for contributing to the main window toolbar subsystem. See ADRs 001–007 for rationale.

## Rules

### 1. Sole router

Only `MainWindowToolbar` routes toolbar content by `AppPage` (until ADR 003 triggers). Do not add `switch activePage` in coordinator, dispatcher, or feature toolbar views.

### 2. Glass-only chrome

Toolbar controls use `GlassToolbarControls` (and the Liquid Glass design system) only. Never add raw `Button`/`Image` chrome for toolbar items.

### 3. Cross-tab store boundary

Page-specific state must never enter types conforming to `CrossTabToolbarState` (`AppToolbarStore`). Feature scene state owns truth; toolbar reads `toolbarProjection`.

### 4. Toolbar actions

New toolbar action → add nested enum case (e.g. `CalendarToolbarAction`), document owner in a comment, and add a unit test for dispatch routing.

### 5. File placement

Feature toolbar content (`*ToolbarContent.swift`) is colocated with the feature or under `App/Toolbar/` until Phase 2 module split (ADR 004).

### 6. Dispatcher lifecycle

Use scoped registration: `toolbarDispatcher.register(owner:)` returns a `ToolbarHandlerToken`. Always call `token.invalidate()` in `.onDisappear` (or equivalent) to prevent stale handlers on fast tab switches.

### 7. No AppKit in toolbar views

SwiftUI toolbar view modules must not `import AppKit`. AppKit toolbar wiring is rejected (ADR 001). Settings window is the documented exception.

### 8. Deprecation window

Deprecated toolbar APIs are removed within two releases (ADR 006). Do not add permanent compatibility wrappers.

## Quick reference

| Task | Where |
| --- | --- |
| Add page toolbar items | Feature `*ToolbarContent.swift`; wire in `MainWindowToolbar` |
| Cross-tab shell state | `AppToolbarStore` only |
| Handle toolbar action | Register handler in feature view; dispatch via `ToolbarDispatcher` |
| Window-scoped services | `AppContainer` in `CollegeApp` — store, dispatcher, and `*SceneState` |
| Visual styling | `College/App/Toolbar/Glass/` — not feature content files |

## Ship gate checklist (before merging toolbar work)

See **[toolbar-ship-gate-signoff.md](toolbar-ship-gate-signoff.md)** for the completed automated sign-off (2026-06-05).

1. `xcodebuild -scheme College -configuration Release build` succeeds (use `CODE_SIGNING_ALLOWED=NO` in local CLI builds if needed).
2. Run toolbar gates locally:
   - `bash scripts/run_toolbar_tests.sh` (includes `testDispatcherTabCycleStress` — 10× handler churn)
   - Seed/update snapshots when visuals change (see `docs/liquid-glass-toolbar.md`).
3. Manual smoke (PR reviewer or author):
   - Cycle tabs 10× (Calendar ↔ Academics ↔ Career ↔ Web) and confirm the toolbar updates correctly.
   - Confirm Calendar header date, view mode selection, and sidebar panel controls behave correctly.
4. Memory/leaks (recommended at PR review):
   - Run Instruments “Leaks” while cycling tabs; automated dispatcher stress tests are not a full substitute.
5. Phase 2 clock:
   - **Owner:** Timothy Leung — **deadline:** 2026-06-19 (ADR 004).
