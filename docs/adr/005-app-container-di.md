# ADR 005: AppContainer Dependency Injection

**Status:** Implemented (main window path — `AppContainer` holds window-scoped services; shared singletons passed by reference)  
**Date:** 2026-06-05

## Context

The app injects an increasing number of services via `@Environment`, `@EnvironmentObject`, and per-window `@State` (persistence, toolbar store, dispatcher, feature scene states). Beyond roughly eight environment keys, injection becomes hard to trace and test.

## Decision (stub)

When environment injection count exceeds ~8 services, introduce a single composition root:

```swift
@Observable
@MainActor
final class AppContainer {
    let persistence: CollegePersistence
    let toolbarStore: AppToolbarStore
    let toolbarDispatcher: ToolbarDispatcher
    // Additional app-wide services
}

// Injection
@Environment(AppContainer.self) private var container
```

### Scope

- **Window-scoped** services (`AppToolbarStore`, `ToolbarDispatcher`) remain per-window instances held by `AppContainer` created in `CollegeApp`, not singletons.
- **Trigger:** Environment injection count > ~8 distinct service types in main window path.
- **Not in scope:** Full DI framework; manual `AppContainer` factory in `CollegeApp` is sufficient.

## Consequences

- **Main window:** `CollegeApp` owns a single `@State appContainer`; views use `@Environment(AppContainer.self)` (toolbar and key feature views migrated). Child environment keys remain via `appContainerEnvironment(_:)` for views not yet migrated.
- **Window-scoped** services remain per-window instances held by `AppContainer`, not singletons.
- **Shared singletons** (`CollegePersistence`, `AppDataStore`, `AppActivityCoordinator`) are passed into `AppContainer` by reference.
- **Testing:** `AppContainer` accepts injectable dependencies for test doubles (see `ToolbarArchitectureTests`).
