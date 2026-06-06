# ADR 003: Toolbar Provider Registry

**Status:** Implemented (provider protocol + per-feature providers; registry delegates from `MainWindowToolbar`)  
**Date:** 2026-06-05

## Context

`MainWindowToolbar` routes toolbar content with a `switch activePage` pattern. This scales to roughly 5–10 pages. Beyond that, the router becomes a maintenance bottleneck and `ToolbarAction` growth makes exhaustive dispatch unwieldy.

## Decision (stub)

When trigger thresholds are met, replace the central switch with a **toolbar provider registry**. Implementation is deferred until needed.

### Trigger conditions (any one)

- `AppPage` count > 10
- `MainWindowToolbar` switch body > ~80 lines
- `ToolbarAction` total case count > 40 (monitored by health-check CI)

### Proposed API

```swift
protocol ToolbarProviding {
    associatedtype Content: ToolbarContent
    @ToolbarContentBuilder
    func toolbarContent(
        store: AppToolbarStore,
        dispatcher: ToolbarDispatcher
    ) -> Content
}

enum ToolbarProviderRegistry {
    @ToolbarContentBuilder
    static func content(
        for page: AppPage,
        store: AppToolbarStore,
        dispatcher: ToolbarDispatcher
    ) -> some ToolbarContent
}
```

Each feature registers its provider; `MainWindowToolbar` delegates to the registry. Maintenance cost becomes **O(feature)** instead of **O(pages)** in one file.

## Consequences

- **Main window:** `ToolbarProviderRegistry` routes each `AppPage` to a `ToolbarProviding` enum (`CalendarToolbarProvider`, etc.). `MainWindowToolbar` builds a `ToolbarProviderContext` (store, dispatcher, active page, academics binding) and delegates.
- **Scale:** Adding a page with toolbar chrome = new provider + registry case + metadata entry — not edits to a monolithic switch body in `MainWindowToolbar`.
- **Not in scope:** `ToolbarRegistry.shared` singleton; providers receive window-scoped store and dispatcher via context parameters (views may still read `@Environment(AppContainer.self)` for scene state).
