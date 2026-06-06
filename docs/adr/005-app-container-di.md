# ADR 005: AppContainer Dependency Injection

**Status:** Fully implemented  
**Date:** 2026-06-05

## Context

The app injects an increasing number of services via `@Environment`, `@EnvironmentObject`, and per-window `@State` (persistence, toolbar store, dispatcher, feature scene states). Beyond roughly eight environment keys, injection becomes hard to trace and test.

## Decision

Introduce a single window-scoped composition root:

```swift
@Observable
@MainActor
final class AppContainer {
    // Shared singletons (by reference)
    let persistence: CollegePersistence
    let appDataStore: AppDataStore
    let appActivity: AppActivityCoordinator
    let appNotifications: AppNotificationCenter
    let securityManager: SecurityManager

    // Window-scoped integration services
    let locationPermissionService: LocationPermissionService
    let calendarManager: CalendarIntegrationManager
    let brightspaceCoordinator: BrightspaceWebCoordinator

    let toolbarStore: AppToolbarStore
    let toolbarDispatcher: ToolbarDispatcher
    // scene states, modalCoordinator, metrics stores, launchPreloadCoordinator
}

// Injection
@Environment(AppContainer.self) private var container
private var collegePersistence: CollegePersistence { container.persistence }
```

### Scope

- **Window-scoped** services (`AppToolbarStore`, `ToolbarDispatcher`, `CalendarIntegrationManager`, `BrightspaceWebCoordinator`, `LocationPermissionService`) are one instance per main window, held by `AppContainer` created in `CollegeApp`.
- **Shared singletons** (`CollegePersistence`, `AppDataStore`, `AppActivityCoordinator`, `AppNotificationCenter`, `SecurityManager`) are passed into `AppContainer` by reference.
- **CalendarIntegrationManager** is window-scoped (not a global singleton) so each window could host independent calendar state; the main app creates one instance via `AppContainer`.
- **Not in scope:** Full DI framework; manual `AppContainer` factory in `CollegeApp` is sufficient.

### Intentionally outside AppContainer

- `SettingsSessionController` — per-settings-window session state (`MacStandaloneSettingsRoot`).
- `WeatherService` / `WidgetConfigurationStore` — overview widget-local stores not wired through `CollegeApp` injection (future: add to container if promoted app-wide).

## Consequences

- `CollegeApp` owns a single `@State appContainer`; all roots use `.appContainerEnvironment(appContainer)` (container + SwiftData `modelContainer`).
- Views use `@Environment(AppContainer.self)` with computed-property aliases for ergonomics; no duplicate child environment keys.
- **Testing:** `AppContainer` accepts injectable dependencies for test doubles (see `ToolbarArchitectureTests`).
