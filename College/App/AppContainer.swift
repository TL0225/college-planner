// AppContainer.swift
// Feature: App
// Purpose: Window-scoped composition root (ADR 005).

import CollegeAcademics
import CollegeCalendar
import CollegeCareer
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
    let emailService: EmailService

    // Window-scoped integration services (one instance per main window)
    let locationPermissionService: LocationPermissionService
    let calendarManager: CalendarIntegrationManager
    let lmsCoordinator: LMSWebCoordinator

    let toolbarStore: AppToolbarStore
    let toolbarDispatcher: ToolbarDispatcher
    let calendarScene: CalendarSceneState
    let academicsScene: AcademicsSceneState
    let assistantScene: AssistantSceneState
    let careerScene: CareerSceneState
    let careerNavigationRouter: CareerNavigationRouter
    let webPortalScene: WebPortalSceneState
    let transferScene: TransferSceneState
    let transferCoordinator: TransferCoordinator

    let modalCoordinator: ModalCoordinator
    let academicMetricsStore: AcademicMetricsStore
    let auditSnapshotStore: AuditSnapshotStore
    let launchPreloadCoordinator: LaunchPreloadCoordinator
    let translationService: TranslationService

    /// Retains calendar shell port adapters (`CalendarToolbarAccess` et al. hold weak refs).
    let calendarShellPorts: CalendarShellPortAdapters

    init(
        persistence: CollegePersistence = .shared,
        appDataStore: AppDataStore = .shared,
        appActivity: AppActivityCoordinator = .shared,
        appNotifications: AppNotificationCenter = .shared,
        securityManager: SecurityManager = .shared,
        emailService: EmailService? = nil,
        locationPermissionService: LocationPermissionService? = nil,
        calendarManager: CalendarIntegrationManager? = nil,
        lmsCoordinator: LMSWebCoordinator? = nil,
        telemetry: ToolbarTelemetrySink = DebugToolbarTelemetry(),
        modalCoordinator: ModalCoordinator? = nil,
        academicMetricsStore: AcademicMetricsStore? = nil,
        auditSnapshotStore: AuditSnapshotStore? = nil,
        launchPreloadCoordinator: LaunchPreloadCoordinator? = nil,
        translationService: TranslationService? = nil,
        toolbarStore: AppToolbarStore? = nil,
        toolbarDispatcher: ToolbarDispatcher? = nil,
        calendarScene: CalendarSceneState? = nil,
        academicsScene: AcademicsSceneState? = nil,
        assistantScene: AssistantSceneState? = nil,
        careerScene: CareerSceneState? = nil,
        careerNavigationRouter: CareerNavigationRouter? = nil,
        webPortalScene: WebPortalSceneState? = nil,
        transferScene: TransferSceneState? = nil,
        transferCoordinator: TransferCoordinator? = nil
    ) {
        self.persistence = persistence
        self.appDataStore = appDataStore
        self.appActivity = appActivity
        self.appNotifications = appNotifications
        self.securityManager = securityManager
        self.emailService = emailService ?? EmailService(persistence: persistence)
        self.locationPermissionService = locationPermissionService ?? LocationPermissionService()
        self.calendarManager = calendarManager ?? CalendarIntegrationManager()
        self.lmsCoordinator = lmsCoordinator ?? LMSWebCoordinator()
        self.modalCoordinator = modalCoordinator ?? ModalCoordinator()
        self.academicMetricsStore = academicMetricsStore ?? AcademicMetricsStore()
        self.auditSnapshotStore = auditSnapshotStore ?? AuditSnapshotStore()
        self.launchPreloadCoordinator = launchPreloadCoordinator ?? LaunchPreloadCoordinator()
        self.translationService = translationService ?? TranslationService()
        self.toolbarStore = toolbarStore ?? AppToolbarStore()
        self.toolbarDispatcher = toolbarDispatcher ?? ToolbarDispatcher(telemetry: telemetry)
        self.calendarScene = calendarScene ?? CalendarSceneState()
        self.academicsScene = academicsScene ?? AcademicsSceneState()
        self.assistantScene = assistantScene ?? AssistantSceneState()
        self.careerScene = careerScene ?? CareerSceneState()
        self.careerNavigationRouter = careerNavigationRouter ?? CareerNavigationRouter()
        self.webPortalScene = webPortalScene ?? WebPortalSceneState()
        let resolvedTransferScene = transferScene ?? TransferSceneState()
        self.transferScene = resolvedTransferScene
        self.transferCoordinator = transferCoordinator ?? TransferCoordinator(
            persistence: persistence,
            scene: resolvedTransferScene
        )
        TransferCoordinatorBridge.wire(self.transferCoordinator)
        self.calendarShellPorts = CalendarShellPortAdapters(
            appNotifications: appNotifications,
            modalCoordinator: self.modalCoordinator,
            toolbarDispatcher: self.toolbarDispatcher
        )
        CalendarPersistencePortBootstrap.wireShell(container: self)
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
            .environment(container.translationService)
            .modelContainer(container.appDataStore.profileContainer)
    }
}
