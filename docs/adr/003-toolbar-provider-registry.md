# ADR 003: Toolbar Provider Registry

**Status:** Accepted (registry implemented; full provider protocol deferred until scale triggers)  
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

- **Until triggered:** ADR 001 rule stands—`MainWindowToolbar` remains the sole router.
- **When triggered:** Schedule registry work with or immediately after Phase 2 platform initiative (ADR 004).
- **Not in scope now:** `ToolbarRegistry.shared` singleton; providers receive window-scoped store and dispatcher as parameters.
