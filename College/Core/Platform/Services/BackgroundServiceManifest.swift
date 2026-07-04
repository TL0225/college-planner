// BackgroundServiceManifest.swift
// Feature: Core/Platform
// Purpose: Tier 1 and Tier 2 background service descriptors for the lifecycle registry.

import CollegeCalendar
import Foundation

enum BackgroundServiceManifest {
    static func allDescriptors() -> [BackgroundServiceDescriptor] {
        tier1AtLaunch
            + tier1AtMainUIReady
            + tier1OnSceneActive
            + tier2OnDemand
    }

    static var allIDs: [String] {
        allDescriptors().map(\.id)
    }

    // MARK: - Tier 1 · atLaunch (sortOrder 0–99)

    private static let tier1AtLaunch: [BackgroundServiceDescriptor] = [
        BackgroundServiceDescriptor(
            id: "network_connectivity",
            displayName: "Network Connectivity",
            activation: .atLaunch,
            sortOrder: 0,
            start: { NetworkConnectivityMonitor.shared.startIfNeeded() },
            stop: { }
        ),
        BackgroundServiceDescriptor(
            id: "memory_pressure",
            displayName: "Memory Pressure",
            activation: .atLaunch,
            sortOrder: 10,
            start: { MemoryPressureHandler.shared.startIfNeeded() },
            stop: { }
        ),
        BackgroundServiceDescriptor(
            id: "runtime_telemetry",
            displayName: "Runtime Telemetry",
            activation: .atLaunch,
            sortOrder: 20,
            start: { RuntimeTelemetryMonitor.shared.startIfNeeded() },
            stop: { }
        ),
        BackgroundServiceDescriptor(
            id: "background_activity_ui",
            displayName: "Background Activity UI",
            activation: .atLaunch,
            sortOrder: 25,
            start: { BackgroundActivityCenter.shared.startObservingProgressNotifications() },
            stop: { }
        ),
        BackgroundServiceDescriptor(
            id: "menu_bar_status",
            displayName: "Menu Bar Status",
            activation: .atLaunch,
            sortOrder: 26,
            start: { CollegeMenuBarStatusModel.shared.startObservingProgressNotifications() },
            stop: { }
        ),
        BackgroundServiceDescriptor(
            id: "catalog_menu_bar_progress",
            displayName: "Catalog Menu Bar Progress",
            activation: .atLaunch,
            sortOrder: 27,
            start: { CatalogMenuBarProgressController.shared.startObservingProgressNotifications() },
            stop: { }
        ),
        BackgroundServiceDescriptor(
            id: "crash_capture",
            displayName: "Crash Capture",
            activation: .atLaunch,
            sortOrder: 30,
            start: {
                CrashReportStore.installSignalCrashCaptureIfNeeded()
                UncaughtExceptionLogger.installIfNeeded()
            },
            stop: { }
        ),
        BackgroundServiceDescriptor(
            id: "mlx_error_handler",
            displayName: "MLX Error Handler",
            activation: .atLaunch,
            sortOrder: 32,
            start: { MLXGlobalErrorHandler.installIfNeeded() },
            stop: { }
        ),
        BackgroundServiceDescriptor(
            id: "session_termination",
            displayName: "Session Termination",
            activation: .atLaunch,
            sortOrder: 35,
            start: { SessionTerminationTracker.markSessionStarted() },
            stop: { SessionTerminationTracker.markCleanTermination() }
        ),
        BackgroundServiceDescriptor(
            id: "diagnostics_event_store",
            displayName: "Diagnostics Event Store",
            activation: .atLaunch,
            sortOrder: 40,
            start: { await DiagnosticsEventStore.shared.openIfNeeded() },
            stop: { }
        ),
        BackgroundServiceDescriptor(
            id: "widget_registry",
            displayName: "Widget Registry",
            activation: .atLaunch,
            sortOrder: 50,
            start: { WidgetRegistry.shared.bootstrapBuiltIns() },
            stop: { }
        ),
        BackgroundServiceDescriptor(
            id: "llm_memory_lifecycle",
            displayName: "LLM Memory Lifecycle",
            activation: .atLaunch,
            sortOrder: 55,
            start: { LLMMemoryLifecycle.shared.cancelIdleRelease() },
            stop: { LLMMemoryLifecycle.shared.cancelIdleRelease() }
        ),
        BackgroundServiceDescriptor(
            id: "catalog_embed_memory_lifecycle",
            displayName: "Catalog Embed Memory Lifecycle",
            activation: .atLaunch,
            sortOrder: 56,
            start: { CatalogEmbedMemoryLifecycle.shared.cancelIdleRelease() },
            stop: { CatalogEmbedMemoryLifecycle.shared.cancelIdleRelease() }
        ),
        BackgroundServiceDescriptor(
            id: "ics_subscription_refresh",
            displayName: "ICS Subscription Refresh",
            activityDomain: .academicCalendar,
            activation: .atLaunch,
            sortOrder: 60,
            start: { ICSSubscriptionRefreshService.shared.start() },
            stop: { ICSSubscriptionRefreshService.shared.stop() }
        ),
        BackgroundServiceDescriptor(
            id: "academic_calendar_refresh",
            displayName: "Academic Calendar Refresh",
            activityDomain: .academicCalendar,
            activation: .atLaunch,
            sortOrder: 70,
            start: { AcademicCalendarRefreshService.shared.start() },
            stop: { AcademicCalendarRefreshService.shared.stop() }
        ),
        BackgroundServiceDescriptor(
            id: "catalog_store_migration",
            displayName: "Catalog Store Migration",
            activityDomain: .catalog,
            activation: .atLaunch,
            resourceLane: .database,
            sortOrder: 80,
            start: {
                CatalogStoreCoordinator.shared.migrateUniversitiesFromCurrentStoreIfNeeded()
            },
            stop: { }
        ),
    ]

    // MARK: - Tier 1 · atMainUIReady

    private static let tier1AtMainUIReady: [BackgroundServiceDescriptor] = [
        BackgroundServiceDescriptor(
            id: "calendar_reminders",
            displayName: "Calendar Reminders",
            activityDomain: .academicCalendar,
            activation: .atMainUIReady,
            sortOrder: 100,
            start: {
                CalendarReminderScheduler.shared.registerNotificationCategories()
                CalendarReminderScheduler.shared.requestAuthorizationIfNeeded()
            },
            stop: { }
        ),
        BackgroundServiceDescriptor(
            id: "calendar_course_linker",
            displayName: "Calendar Course Linker",
            activityDomain: .academicCalendar,
            activation: .atMainUIReady,
            resourceLane: .database,
            sortOrder: 110,
            start: { await CalendarCourseLinker.shared.scanAndLink() },
            stop: { }
        ),
        BackgroundServiceDescriptor(
            id: "fs_watchdog",
            displayName: "Filesystem Watchdog",
            activation: .atMainUIReady,
            sortOrder: 120,
            start: { FSWatchdogService.shared.startWatching() },
            stop: { FSWatchdogService.shared.stopWatching() }
        ),
        BackgroundServiceDescriptor(
            id: "stale_file_monitor",
            displayName: "Stale File Monitor",
            activation: .atMainUIReady,
            throttle: .pauseWhenInactive,
            sortOrder: 130,
            start: { StaleFileMonitor.shared.startMonitoring() },
            stop: { StaleFileMonitor.shared.stopMonitoring() },
            pause: { StaleFileMonitor.shared.stopMonitoring() },
            resume: { StaleFileMonitor.shared.startMonitoring() }
        ),
        BackgroundServiceDescriptor(
            id: "screenshot_triage",
            displayName: "Screenshot Triage",
            activation: .atMainUIReady,
            throttle: .pauseWhenInactive,
            sortOrder: 140,
            start: { VaultScreenshotTriage.shared.scheduleDailyScan() },
            stop: { VaultScreenshotTriage.shared.stopDailyScan() },
            pause: { VaultScreenshotTriage.shared.stopDailyScan() },
            resume: { VaultScreenshotTriage.shared.scheduleDailyScan() }
        ),
        BackgroundServiceDescriptor(
            id: "weekly_digest",
            displayName: "Weekly Digest",
            activation: .atMainUIReady,
            sortOrder: 150,
            start: { VaultWeeklyDigest.shared.scheduleWeeklyDigest() },
            stop: { }
        ),
        BackgroundServiceDescriptor(
            id: "cloud_integration_rescan",
            displayName: "Cloud Integration Rescan",
            activation: .atMainUIReady,
            sortOrder: 160,
            start: { CloudIntegrationService.shared.startAutoRescan() },
            stop: { CloudIntegrationService.shared.stopAutoRescan() }
        ),
        BackgroundServiceDescriptor(
            id: "catalog_vector_observer",
            displayName: "Catalog Vector Observer",
            activityDomain: .catalog,
            activation: .atMainUIReady,
            sortOrder: 170,
            start: { CatalogVectorIndexingLifecycle.start() },
            stop: { }
        ),
        BackgroundServiceDescriptor(
            id: "model_bootstrap",
            displayName: "Model Bootstrap",
            activityDomain: .aiModel,
            activation: .atMainUIReady,
            resourceLane: .fileIO,
            sortOrder: 180,
            start: { await ModelBootstrapService.ensureModelReady() },
            stop: { }
        ),
        BackgroundServiceDescriptor(
            id: "diagnostics_bootstrap",
            displayName: "Diagnostics Bootstrap",
            activation: .atMainUIReady,
            sortOrder: 190,
            start: { DiagnosticsBootstrap.startDeferredServices() },
            stop: { }
        ),
        BackgroundServiceDescriptor(
            id: "semester_archive_check",
            displayName: "Semester Archive Check",
            activation: .atMainUIReady,
            resourceLane: .fileIO,
            sortOrder: 195,
            start: { await VaultSemesterArchive.shared.checkForSemesterChange() },
            stop: { }
        ),
    ]

    // MARK: - Tier 1 · onSceneActive

    private static let tier1OnSceneActive: [BackgroundServiceDescriptor] = [
        BackgroundServiceDescriptor(
            id: "planner_vector_lifecycle",
            displayName: "Planner Vector Lifecycle",
            activityDomain: .vaultIndexing,
            activation: .onSceneActive(.assistant),
            sortOrder: 200,
            start: { PlannerVectorIndexingLifecycle.start() },
            stop: { }
        ),
        BackgroundServiceDescriptor(
            id: "job_board_sync",
            displayName: "Job Board Sync",
            activityDomain: .careerJobBoard,
            activation: .onSceneActive(.career),
            sortOrder: 200,
            start: { JobBoardSyncCoordinator.shared.start() },
            stop: { JobBoardRefreshScheduler.shared.stop() }
        ),
        BackgroundServiceDescriptor(
            id: "job_board_notifications",
            displayName: "Job Board Notifications",
            activityDomain: .careerJobBoard,
            activation: .onSceneActive(.career),
            sortOrder: 210,
            start: { await JobBoardNotificationService.shared.requestPermissionIfNeeded() },
            stop: { }
        ),
        BackgroundServiceDescriptor(
            id: "career_ingest",
            displayName: "Career Ingest",
            activityDomain: .careerResume,
            activation: .onSceneActive(.career),
            sortOrder: 220,
            start: {
                await CareerIngestCoordinator.shared.processPendingIngestIfNeeded()
                await CareerIngestCoordinator.shared.processPendingSaveRequests()
            },
            stop: { }
        ),
        BackgroundServiceDescriptor(
            id: "career_follow_up",
            displayName: "Career Follow-Up",
            activityDomain: .careerJobBoard,
            activation: .onSceneActive(.career),
            sortOrder: 230,
            start: { CareerFollowUpScheduler.shared.reconcile(using: CollegePersistence.shared) },
            stop: { }
        ),
        BackgroundServiceDescriptor(
            id: "calendar_provider_sync",
            displayName: "Calendar Provider Sync",
            activityDomain: .academicCalendar,
            activation: .onSceneActive(.calendar),
            throttle: .pauseWhenInactive,
            sortOrder: 200,
            start: {
                if let manager = CalendarIntegrationBridge.manager {
                    AcademicCalendarIntegration.syncAllRegistrations(calendarManager: manager)
                    manager.startProviderBackgroundSyncLoops()
                }
            },
            stop: {
                CalendarIntegrationBridge.manager?.stopProviderBackgroundSyncLoops()
            },
            pause: {
                CalendarIntegrationBridge.manager?.stopProviderBackgroundSyncLoops()
            },
            resume: {
                CalendarIntegrationBridge.manager?.startProviderBackgroundSyncLoops()
            }
        ),
        BackgroundServiceDescriptor(
            id: "transfer_database_bootstrap",
            displayName: "Transfer Database Bootstrap",
            activation: .onSceneActive(.transferDatabase),
            sortOrder: 200,
            start: { TransferCoordinatorBridge.bootstrapIfNeeded() },
            stop: { }
        ),
    ]

    // MARK: - Tier 2 · onDemand

    private static let tier2OnDemand: [BackgroundServiceDescriptor] = [
        onDemand(id: "launch_preload_pipeline", displayName: "Launch Preload Pipeline"),
        onDemand(id: "catalog_background_sync", displayName: "Catalog Background Sync", domain: .catalog),
        onDemand(id: "catalog_ingest_coordinator", displayName: "Catalog Ingest", domain: .catalog),
        onDemand(id: "catalog_school_purge", displayName: "Catalog School Purge", domain: .catalogPurge),
        onDemand(id: "catalog_school_import", displayName: "Catalog School Import", domain: .catalog),
        onDemand(id: "catalog_session_warmup", displayName: "Catalog Session Warmup", domain: .catalog),
        onDemand(id: "catalog_vector_reindex", displayName: "Catalog Vector Reindex", domain: .catalog),
        onDemand(id: "program_requirements_scrape", displayName: "Program Requirements Scrape", domain: .catalog),
        onDemand(id: "academic_calendar_import", displayName: "Academic Calendar Import", domain: .academicCalendar),
        onDemand(id: "academic_notification_reschedule", displayName: "Academic Notification Reschedule", domain: .academicCalendar),
        onDemand(id: "calendar_sync_ingest", displayName: "Calendar Sync Ingest", domain: .academicCalendar),
        onDemand(id: "calendar_sync_export", displayName: "Calendar Sync Export", domain: .academicCalendar),
        onDemand(id: "vault_text_index", displayName: "Vault Text Index", domain: .vaultIndexing),
        onDemand(id: "vault_spotlight_index", displayName: "Vault Spotlight Index", domain: .vaultIndexing),
        onDemand(id: "vault_semester_archive", displayName: "Vault Semester Archive", domain: .vaultIndexing),
        onDemand(id: "vault_file_organize", displayName: "Vault File Organize", domain: .vaultIndexing),
        onDemand(id: "vault_share_bundle", displayName: "Vault Share Bundle", domain: .vaultIndexing),
        onDemand(id: "document_classifier", displayName: "Document Classifier", domain: .vaultIndexing),
        onDemand(id: "career_resume_ingest", displayName: "Career Resume Ingest", domain: .careerResume),
        onDemand(id: "career_resume_enrichment", displayName: "Career Resume Enrichment", domain: .careerResume),
        onDemand(id: "career_ai_parse", displayName: "Career AI Parse", domain: .careerResume),
        onDemand(id: "career_ats_lookup", displayName: "Career ATS Lookup", domain: .careerResume),
        onDemand(id: "career_spotlight_index", displayName: "Career Spotlight Index", domain: .careerResume),
        onDemand(id: "app_backup_export", displayName: "App Backup Export"),
        onDemand(id: "app_backup_import", displayName: "App Backup Import"),
        onDemand(id: "transfer_refresh", displayName: "Transfer Refresh"),
        onDemand(id: "community_transfer_import", displayName: "Community Transfer Import"),
        onDemand(id: "degoog_sidecar", displayName: "DeGoog Sidecar", domain: .aiModel),
        onDemand(id: "local_llm_inference", displayName: "Local LLM Inference", domain: .aiModel),
        onDemand(id: "llm_on_demand_prewarm", displayName: "LLM On-Demand Prewarm", domain: .aiModel),
        onDemand(id: "model_migration", displayName: "Model Migration", domain: .aiModel),
        onDemand(id: "catalog_mlx_embed", displayName: "Catalog MLX Embed", domain: .aiModel),
        onDemand(id: "planner_vector_rebuild", displayName: "Planner Vector Rebuild", domain: .vaultIndexing),
        onDemand(id: "assistant_attachment_ingest", displayName: "Assistant Attachment Ingest", domain: .vaultIndexing),
        onDemand(id: "assistant_reply_generation", displayName: "Assistant Reply Generation", domain: .aiModel),
        onDemand(id: "app_update_check", displayName: "App Update Check"),
        onDemand(id: "data_wipe", displayName: "Data Wipe"),
    ]

    private static func onDemand(
        id: String,
        displayName: String,
        domain: BackgroundActivityDomain? = nil
    ) -> BackgroundServiceDescriptor {
        BackgroundServiceDescriptor(
            id: id,
            displayName: displayName,
            activityDomain: domain,
            activation: .onDemand,
            start: { },
            stop: { }
        )
    }
}
