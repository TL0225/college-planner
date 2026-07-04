# ADR 001: Toolbar Architecture

**Status:** Accepted  
**Date:** 2026-06-05

## Context

The main window historically maintained two toolbar render paths: an active SwiftUI `.toolbar { MainWindowToolbar }` path and a dormant `NSToolbarDelegate` path in `AppToolbarCoordinator`. Dual ownership caused drift risk—titles, placement, and state could diverge between renderers. Per-page toolbar state was also scattered across coordinator fields, sibling `*ToolbarState` observables, and feature views.

## Decision

### Authoritative renderer

SwiftUI `.toolbar { MainWindowToolbar }` in `ContentView` is the **sole** toolbar renderer for the main window. The `NSToolbarDelegate` path (`attach(to:)`, item factories, identifier routing) is **rejected** and removed.

### State ownership

| Concern | Owner |
| --- | --- |
| Feature UI truth | `*SceneState` (e.g. `CalendarSceneState`) |
| Toolbar display | `sceneState.toolbarProjection` — derived, not stored duplicate |
| Cross-tab / shell only | `AppToolbarStore` conforming to `CrossTabToolbarState` |

**Hard rule:** `AppToolbarStore` must never contain page-specific display state (no `calendarTitle`, `calendarMode`, etc.).

Toolbar views read projections; mutations flow through `ToolbarDispatcher` → feature handler → scene state update.

### Panel visibility taxonomy

- **App navigation sidebar:** `NavigationSplitViewVisibility` in `ContentView` (left column).
- **Feature inspector panels:** e.g. `calendarScene.sidebarShown` (calendar right event list), `academicsScene.statsSidebarShown` (academics stats column). These are feature-local today; unifying cross-tab panel chrome in shell state is a follow-up if needed.

### Native Liquid Glass chrome

Window toolbar controls use macOS 26 native APIs (`.buttonStyle(.glass)`, `GlassEffectContainer`) inline in `App/Toolbar/**`. Feature `*ToolbarContent` files describe **what** appears; they dispatch actions rather than mutating feature state directly.

### Sole router

`MainWindowToolbar` is the only place that routes toolbar content by `AppPage` (until ADR 003 triggers). No `switch activePage` in coordinator, dispatcher, or per-feature toolbar views.

### Settings exception

The standalone Settings scene is **out of scope** for this refactor and does not share `AppToolbarStore`, `ToolbarDispatcher`, or `MainWindowToolbar`. Its toolbar/sidebar is owned **entirely by SwiftUI**: `NavigationSplitView` in `SettingsView` provides the native sidebar toggle, and `SettingsView` attaches its own SwiftUI `.toolbar` for back/forward history. `SettingsSessionController` no longer installs a custom `NSToolbarDelegate`/`NSToolbar` (doing so previously caused the sidebar button to duplicate and jump sides between sections); it now only tracks section/history state and applies lightweight window chrome.

## Consequences

- **Positive:** Single source of truth (`ContentView → MainWindowToolbar`); eliminates renderer drift; clear state boundaries.
- **Positive:** Feature modules own truth; toolbar is a read-only projection.
- **Negative:** `AppToolbarCoordinator` is deleted; all consumers migrate to store + dispatcher + projections.
- **Follow-up:** ADR 002 (window scoping), ADR 006 (deprecation), ADR 007 (Liquid Glass design system).
