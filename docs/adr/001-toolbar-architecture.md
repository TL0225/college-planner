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

### Glass-only UI primitives

All toolbar chrome uses `GlassToolbarControls` (and the Liquid Glass design system in ADR 007). Feature `*ToolbarContent` files describe **what** appears; they do not set materials, padding, or animations directly. No raw `Button`/`Image` chrome in toolbar views.

### Sole router

`MainWindowToolbar` is the only place that routes toolbar content by `AppPage` (until ADR 003 triggers). No `switch activePage` in coordinator, dispatcher, or per-feature toolbar views.

### Settings exception

The Settings window (`SettingsSessionController`) retains its own `NSToolbarDelegate` for unified settings chrome. It is **out of scope** for this refactor and does not share `AppToolbarStore`, `ToolbarDispatcher`, or `MainWindowToolbar`.

## Consequences

- **Positive:** Single source of truth (`ContentView → MainWindowToolbar`); eliminates renderer drift; clear state boundaries.
- **Positive:** Feature modules own truth; toolbar is a read-only projection.
- **Negative:** `AppToolbarCoordinator` is deleted; all consumers migrate to store + dispatcher + projections.
- **Follow-up:** ADR 002 (window scoping), ADR 006 (deprecation), ADR 007 (Liquid Glass design system).
