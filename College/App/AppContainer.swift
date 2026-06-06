// AppContainer.swift
// Feature: App
// Purpose: Window-scoped composition root (ADR 005).

import Foundation
import Observation
import SwiftData
import SwiftUI

@Observable
@MainActor
final class AppContainer {
    // Shared singletons (passed by reference, not owned per window)
    let persistence: CollegePersistence
    let appDataStore: AppDataStore
    let appActivity: AppActivityCoordinator
    let appNotifications: AppNotificationCenter
    let securityManager: SecurityManager

    // Window-scoped integration services (one instance per main window)
    let locationPermissionService: LocationPermissionService
    let calendarManager: CalendarIntegrationManager
    let brightspaceCoordinator: BrightspaceWebCoordinator

    let toolbarStore: AppToolbarStore
    let toolbarDispatcher: ToolbarDispatcher
    let calendarScene: CalendarSceneState
    let academicsScene: AcademicsSceneState
    let careerScene: CareerSceneState
    let webPortalScene: WebPortalSceneState

    let modalCoordinator: ModalCoordinator
    let academicMetricsStore: AcademicMetricsStore
    let auditSnapshotStore: AuditSnapshotStore
    let launchPreloadCoordinator: LaunchPreloadCoordinator

    init(
        persistence: CollegePersistence = .shared,
        appDataStore: AppDataStore = .shared,
        appActivity: AppActivityCoordinator = .shared,
        appNotifications: AppNotificationCenter = .shared,
        securityManager: SecurityManager = .shared,
        locationPermissionService: LocationPermissionService? = nil,
        calendarManager: CalendarIntegrationManager? = nil,
        brightspaceCoordinator: BrightspaceWebCoordinator? = nil,
        telemetry: ToolbarTelemetrySink = DebugToolbarTelemetry(),
        modalCoordinator: ModalCoordinator? = nil,
        academicMetricsStore: AcademicMetricsStore? = nil,
        auditSnapshotStore: AuditSnapshotStore? = nil,
        launchPreloadCoordinator: LaunchPreloadCoordinator? = nil,
        toolbarStore: AppToolbarStore? = nil,
        toolbarDispatcher: ToolbarDispatcher? = nil,
        calendarScene: CalendarSceneState? = nil,
        academicsScene: AcademicsSceneState? = nil,
        careerScene: CareerSceneState? = nil,
        webPortalScene: WebPortalSceneState? = nil
    ) {
        self.persistence = persistence
        self.appDataStore = appDataStore
        self.appActivity = appActivity
        self.appNotifications = appNotifications
        self.securityManager = securityManager
        self.locationPermissionService = locationPermissionService ?? LocationPermissionService()
        self.calendarManager = calendarManager ?? CalendarIntegrationManager()
        self.brightspaceCoordinator = brightspaceCoordinator ?? BrightspaceWebCoordinator()
        self.modalCoordinator = modalCoordinator ?? ModalCoordinator()
        self.academicMetricsStore = academicMetricsStore ?? AcademicMetricsStore()
        self.auditSnapshotStore = auditSnapshotStore ?? AuditSnapshotStore()
        self.launchPreloadCoordinator = launchPreloadCoordinator ?? LaunchPreloadCoordinator()
        self.toolbarStore = toolbarStore ?? AppToolbarStore()
        self.toolbarDispatcher = toolbarDispatcher ?? ToolbarDispatcher(telemetry: telemetry)
        self.calendarScene = calendarScene ?? CalendarSceneState()
        self.academicsScene = academicsScene ?? AcademicsSceneState()
        self.careerScene = careerScene ?? CareerSceneState()
        self.webPortalScene = webPortalScene ?? WebPortalSceneState()
    }

    /// Main window factory; shared singletons are passed by reference, not owned per window.
    static func makeMainWindow(
        persistence: CollegePersistence = .shared,
        appDataStore: AppDataStore = .shared,
        appActivity: AppActivityCoordinator = .shared,
        appNotifications: AppNotificationCenter = .shared,
        securityManager: SecurityManager = .shared,
        telemetry: ToolbarTelemetrySink = DebugToolbarTelemetry()
    ) -> AppContainer {
        AppContainer(
            persistence: persistence,
            appDataStore: appDataStore,
            appActivity: appActivity,
            appNotifications: appNotifications,
            securityManager: securityManager,
            telemetry: telemetry
        )
    }
}

extension View {
    /// Primary ADR 005 injection path — single `AppContainer` environment key.
    @MainActor
    func appContainerEnvironment(_ container: AppContainer) -> some View {
        environment(container)
            .modelContainer(container.appDataStore.profileContainer)
    }
}
