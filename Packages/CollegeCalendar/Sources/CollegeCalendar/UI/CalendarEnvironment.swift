import SwiftUI

private struct CalendarPersistenceEnvironmentKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: (any CalendarPersistencePort)? = nil
}

private struct CalendarIntegrationManagerEnvironmentKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue: CalendarIntegrationManager? = nil
}

private struct CalendarSceneStateEnvironmentKey: EnvironmentKey {
    static var defaultValue: CalendarSceneState? { nil }
}

public extension EnvironmentValues {
    var calendarPersistence: (any CalendarPersistencePort)? {
        get { self[CalendarPersistenceEnvironmentKey.self] }
        set { self[CalendarPersistenceEnvironmentKey.self] = newValue }
    }

    var calendarIntegrationManager: CalendarIntegrationManager? {
        get { self[CalendarIntegrationManagerEnvironmentKey.self] }
        set { self[CalendarIntegrationManagerEnvironmentKey.self] = newValue }
    }

    var calendarSceneState: CalendarSceneState? {
        get { self[CalendarSceneStateEnvironmentKey.self] }
        set { self[CalendarSceneStateEnvironmentKey.self] = newValue }
    }
}

public extension View {
    func calendarPackageEnvironment(
        persistence: (any CalendarPersistencePort)? = nil,
        integrationManager: CalendarIntegrationManager? = nil,
        sceneState: CalendarSceneState? = nil
    ) -> some View {
        environment(\.calendarPersistence, persistence ?? CalendarPersistenceAccess.persistence)
            .environment(\.calendarIntegrationManager, integrationManager ?? CalendarIntegrationBridge.manager)
            .environment(\.calendarSceneState, sceneState)
    }
}
