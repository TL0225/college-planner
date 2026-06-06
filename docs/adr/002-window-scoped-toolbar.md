# ADR 002: Window-Scoped Toolbar Services

**Status:** Accepted  
**Date:** 2026-06-05

## Context

Toolbar state and action dispatch were centralized in `AppToolbarCoordinator`, a per-`ContentView` instance that mixed cross-tab state, page callbacks, and dormant AppKit wiring. A singleton `ToolbarDispatcher.shared` or `AppToolbarStore.shared` would block correct multi-window behavior and create handler races when users open multiple main windows.

## Decision

`AppToolbarStore` and `ToolbarDispatcher` are **window-scoped**. They are created once per `WindowGroup` instance and injected via SwiftUI environment—not shared singletons.

```swift
// CollegeApp.swift — per WindowGroup
@State private var appToolbarStore = AppToolbarStore()
@State private var toolbarDispatcher = ToolbarDispatcher()
```

Injection:

```swift
.environment(appToolbarStore)
.environment(toolbarDispatcher)
```

### Rules

1. **Never** use `static let shared`, `ToolbarDispatcher.shared`, or global mutable toolbar state.
2. Each window owns its own store, dispatcher, and handler registrations.
3. `ToolbarDispatcher.register(owner:)` returns a `ToolbarHandlerToken`; tokens must be `invalidate()`d on view disappear to prevent stale closures on fast tab switches.
4. `ToolbarTelemetrySink` is injected into the dispatcher per window (default: `NoOpToolbarTelemetry`).

## Consequences

- **Positive:** Correct foundation for multi-window without rewrite.
- **Positive:** Handler lifecycle is scoped to the window that registered them.
- **Negative:** Tests must construct store + dispatcher per test case or use dedicated test hosts—not global fixtures.
- **Rejected:** Singleton dispatcher pattern used by many SwiftUI tutorials.
