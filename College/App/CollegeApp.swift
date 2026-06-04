// CollegeApp.swift
// Feature: App
// Purpose: App module — CollegeApp.
// Data: CollegePersistence / repositories when applicable.

//
//  CollegeApp.swift
//  College
//
//  Created by Timothy Leung on 12/20/25.
//

import SwiftUI

import AppKit
import SwiftData

@main
struct CollegeApp: App {
    @NSApplicationDelegateAdaptor(CollegeAppDelegate.self) private var collegeAppDelegate

    @StateObject private var collegePersistence = CollegePersistence.shared
    @StateObject private var appDataStore = AppDataStore.shared
    @State private var academicMetricsStore = AcademicMetricsStore()
    @State private var auditSnapshotStore = AuditSnapshotStore()
    @State private var modalCoordinator = ModalCoordinator()
    @StateObject private var appNotifications = AppNotificationCenter.shared
    @StateObject private var locationPermissionService = LocationPermissionService()
    @StateObject private var calendarManager = CalendarIntegrationManager()
    @State private var appToolbarCoordinator = AppToolbarCoordinator()
    @StateObject private var securityManager = SecurityManager.shared
    @StateObject private var brightspaceCoordinator = BrightspaceWebCoordinator()
    @State private var launchPreloadCoordinator = LaunchPreloadCoordinator()
    @State private var appActivity = AppActivityCoordinator.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboarding.completed.v1") private var onboardingCompleted: Bool = false
    @State private var showSessionInterruptedAlert = false
    @State private var pendingCrashReportURL: URL?
    @State private var launchMinimumDisplayElapsed = false
    @State private var launchSplashShownAt: Date?
    private let launchSplashMinimumSeconds: TimeInterval = 1.4
    @State private var calendarToolbar = CalendarToolbarState()
    @State private var webPortalToolbar = WebPortalToolbarState()
    @State private var careerToolbar = CareerToolbarState()
    @State private var academicsToolbar = AcademicsToolbarState()
    @AppStorage(CalendarTimeZonePreference.storageKey) private var calendarTimeZoneSelection: String = CalendarTimeZonePreference.systemValue
    @AppStorage("appAppearance") private var appAppearanceRaw: String = AppAppearance.system.rawValue

    private var selectedTimeZone: TimeZone {
        CalendarTimeZonePreference.resolvedTimeZone(selection: calendarTimeZoneSelection)
    }

    private var selectedCalendar: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.timeZone = selectedTimeZone
        return calendar
    }

    private var forceUITestMainUI: Bool { UITestLaunchFlags.forcesMainUI }
    /// Unit tests host inside `College.app`; avoid full UI, launch preload, and background services.
    private var isHostedUnitTest: Bool {
        CollegeTestRuntime.isUnitTestProcess && !forceUITestMainUI
    }
    private var canLeaveLaunchScreen: Bool {
        forceUITestMainUI || (launchPreloadCoordinator.isCompleted && launchMinimumDisplayElapsed)
    }

    /// XCTest snapshots were missing the main window entirely until the app was activated
    /// and key; this mirrors what a user does when clicking the dock icon.
    private func activateForUITestsIfNeeded() {
        guard forceUITestMainUI else { return }
        UITestLaunchFlags.activateMainWindowIfUITestBoot()
    }

    private var shouldShowOnboarding: Bool {
        if forceUITestMainUI { return false }
        guard launchPreloadCoordinator.isCompleted, collegePersistence.isStoreLoaded else { return false }

        // Finished onboarding is stored in UserDefaults, not inferred from SQLite alone.
        if onboardingCompleted { return false }

        let noPlans = collegePersistence.plans.isEmpty
            && ((try? appDataStore.profileRepository.fetchPlans(limit: 1).isEmpty) ?? true)
        let noSemesters = collegePersistence.semesters.isEmpty
            && ((try? appDataStore.profileRepository.fetchSemesters(limit: 1).isEmpty) ?? true)
        guard noPlans, noSemesters else { return false }

        if hasEstablishedAcademicIdentity(in: collegePersistence) { return false }

        return true
    }

    /// True when the user has committed school + degree level + at least one major (legacy columns or JSON lists).
    private func hasEstablishedAcademicIdentity(in persistence: CollegePersistence) -> Bool {
        if persistence.academicProfiles.contains(where: academicProfileHasCoreIdentity) {
            return true
        }
        guard let profile = persistence.profile else { return false }
        return legacyProfileHasCoreIdentity(profile, persistence: persistence)
    }

    private func academicProfileHasCoreIdentity(_ profile: AcademicProfile) -> Bool {
        let school = (profile.collegeName ?? profile.profile?.collegeName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let degree = (profile.degreeLevel ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasMajor = !AcademicProfileProgramLists.majors(from: profile).isEmpty
            || !(profile.major ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return !school.isEmpty && !degree.isEmpty && hasMajor
    }

    private func legacyProfileHasCoreIdentity(_ profile: Profile, persistence: CollegePersistence) -> Bool {
        let school = (profile.collegeName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let degree = persistence.primaryDegreeLevel(default: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasMajor = !persistence.resolvedMajorNames().isEmpty
        return !school.isEmpty && !degree.isEmpty && hasMajor
    }

    init() {
        UITestLaunchFlags.applyInjectedUserDefaultsIfNeeded()
        if CollegeTestRuntime.isUnitTestProcess, !UITestLaunchFlags.forcesMainUI {
            return
        }
        UserDefaultsWindowAutosaveCleanup.runAtLaunch()
        // Initialize production logger immediately on app launch.
        // Also capture stdout/stderr so print() + runtime warnings are preserved.
        AppLogger.shared.redirectConsoleOutput()
        RuntimeTelemetryMonitor.shared.startIfNeeded()
        RuntimeTelemetryMonitor.shared.markServiceState("app", state: "initializing")
        LaunchPreloadCoordinator.bootstrapBuiltInFeaturePreloadsIfNeeded()
        ModelMigrationService.runLaunchMigrationsIfNeeded()
        WidgetRegistry.shared.bootstrapBuiltIns()

        let logger = DebugLogger.shared
        logger.app("🚀 App init")
        logger.app("Date: \(Date())")
        logger.app("Locale: \(Locale.current.identifier)")
        logger.app("TimeZone: \(TimeZone.current.identifier)")
        logger.app("ProcessInfo: \(ProcessInfo.processInfo.processName)")
        logger.app("OS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        let platform = AppleSiliconPlatform.report
        logger.app("Platform: \(platform.deviceName) — Apple Silicon supported: \(platform.isSupported)")
        if let reason = platform.requirementMessage {
            logger.app("Platform: \(reason)")
        }

        #if DEBUG
        Task.detached(priority: .background) { UnlockDebugLog.ensureFileExists() }
        UnlockDebugLog.log("=== App Session Start ===")
        UnlockDebugLog.log("date=\(Date())")
        UnlockDebugLog.log("locale=\(Locale.current.identifier)")
        UnlockDebugLog.log("tz=\(TimeZone.current.identifier)")
        UnlockDebugLog.log("process=\(ProcessInfo.processInfo.processName)")
        UnlockDebugLog.log("os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
        UnlockDebugLog.log("===")
        #endif

        MLXGlobalErrorHandler.installIfNeeded()
        CrashReportStore.installSignalCrashCaptureIfNeeded()
        UncaughtExceptionLogger.installIfNeeded()
        CatalogMenuBarProgressController.shared.startObservingProgressNotifications()
        CollegeMenuBarStatusModel.shared.startObservingProgressNotifications()
        MemoryPressureHandler.shared.startIfNeeded()

        RuntimeTelemetryMonitor.shared.markServiceState("app", state: "initialized")
    }

    private func applyMacAppearance(from rawValue: String) {
        let appearance = AppAppearance(rawValue: rawValue) ?? .system
        switch appearance {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }

        #if DEBUG
        UnlockDebugLog.log("CollegeApp: NSApp.appearance <- \(appearance.rawValue)")
        #endif
    }

    private func applyInactiveServiceThrottle(_ throttled: Bool) {
        if throttled {
            StaleFileMonitor.shared.stopMonitoring()
            VaultScreenshotTriage.shared.stopDailyScan()
            RuntimeTelemetryMonitor.shared.markServiceState("stale_file_monitor", state: "paused")
            RuntimeTelemetryMonitor.shared.markServiceState("screenshot_triage", state: "paused")
        } else {
            StaleFileMonitor.shared.startMonitoring()
            VaultScreenshotTriage.shared.scheduleDailyScan()
            RuntimeTelemetryMonitor.shared.markServiceState("stale_file_monitor", state: "running")
            RuntimeTelemetryMonitor.shared.markServiceState("screenshot_triage", state: "running")
        }
    }

    private func startTrackedServiceTask(
        _ name: String,
        priority: TaskPriority = .background,
        marksCompleted: Bool = true,
        operation: @escaping @Sendable () async -> Void
    ) {
        RuntimeTelemetryMonitor.shared.markServiceState(name, state: "starting")
        Task.detached(priority: priority) {
            RuntimeTelemetryMonitor.shared.markServiceState(name, state: "running")
            await operation()
            if marksCompleted {
                RuntimeTelemetryMonitor.shared.markServiceState(name, state: "completed")
            }
        }
    }

    @ViewBuilder
    private func onboardingRoot() -> some View {
        OnboardingRootView {
            onboardingCompleted = true
            if !UserDefaults.standard.bool(forKey: OnboardingPreferenceBridge.deepCatalogScrapeCompletedKey) {
                UserDefaults.standard.set(true, forKey: OnboardingPreferenceBridge.showDeepCatalogPromptKey)
            }
        }
        .environmentObject(collegePersistence)
        .environmentObject(appDataStore)
        .environment(launchPreloadCoordinator)
        .environment(\.timeZone, selectedTimeZone)
        .environment(\.calendar, selectedCalendar)
        .environment(modalCoordinator)
        .environmentObject(appNotifications)
        .environmentObject(calendarManager)
        .environmentObject(locationPermissionService)
        .environmentObject(securityManager)
        .environmentObject(brightspaceCoordinator)
        .environment(appActivity)
        .environment(appToolbarCoordinator)
        .modelContainer(appDataStore.profileContainer)
    }

    @ViewBuilder
    private func mainRoot() -> some View {
        ContentView()
            .environmentObject(collegePersistence)
            .environmentObject(appDataStore)
            .modelContainer(appDataStore.profileContainer)
            .environment(academicMetricsStore)
            .environment(\.timeZone, selectedTimeZone)
            .environment(\.calendar, selectedCalendar)
            .environment(modalCoordinator)
            .environmentObject(appNotifications)
            .environmentObject(calendarManager)
            .environmentObject(locationPermissionService)
            .environmentObject(securityManager)
            .environmentObject(brightspaceCoordinator)
            .environment(launchPreloadCoordinator)
            .environment(appActivity)
            .environment(WidgetRegistry.shared)
            .environment(appToolbarCoordinator)
            .environment(calendarToolbar)
            .environment(webPortalToolbar)
            .environment(careerToolbar)
            .environment(academicsToolbar)
            .environment(auditSnapshotStore)
            .onOpenURL { url in
                _ = CollegeInboundURLDispatcher.handle(url) { _ in
                }
            }
            .handlesExternalEvents(preferring: ["college"], allowing: ["*"])
            .onAppear {
                guard !isHostedUnitTest else { return }
                Task { @MainActor in
                    academicMetricsStore.refresh()
                }
                DebugLogger.shared.lifecycle("WindowGroup ContentView appeared")
                applyInactiveServiceThrottle(appActivity.isResourceThrottled)
                AppNotificationCenter.shared.requestPermission()
                CalendarReminderScheduler.shared.registerNotificationCategories()
                CalendarReminderScheduler.shared.requestAuthorizationIfNeeded()

                applyMacAppearance(from: appAppearanceRaw)
                CatalogMenuBarProgressController.shared.startObservingProgressNotifications()
        CollegeMenuBarStatusModel.shared.startObservingProgressNotifications()
                if UserDefaults.standard.bool(forKey: OnboardingPreferenceBridge.catalogSyncInFlightKey) {
                    CatalogMenuBarProgressNotifier.postInProgress(
                        fraction: 0.02,
                        title: "Finishing catalog import",
                        indeterminate: true
                    )
                }

                startTrackedServiceTask("model_bootstrap") {
                    await ModelBootstrapService.ensureModelReady()
                }
                startTrackedServiceTask("fs_watchdog", marksCompleted: false) {
                    await FSWatchdogService.shared.startWatching()
                    RuntimeTelemetryMonitor.shared.markServiceState("fs_watchdog", state: "running")
                }
                startTrackedServiceTask("stale_file_monitor", marksCompleted: false) {
                    await StaleFileMonitor.shared.startMonitoring()
                    RuntimeTelemetryMonitor.shared.markServiceState("stale_file_monitor", state: "running")
                }
                startTrackedServiceTask("screenshot_triage", marksCompleted: false) {
                    await VaultScreenshotTriage.shared.scheduleDailyScan()
                    RuntimeTelemetryMonitor.shared.markServiceState("screenshot_triage", state: "running")
                }
                startTrackedServiceTask("weekly_digest", marksCompleted: false) {
                    await VaultWeeklyDigest.shared.scheduleWeeklyDigest()
                }
                startTrackedServiceTask("semester_archive_check") {
                    await VaultSemesterArchive.shared.checkForSemesterChange()
                }
                startTrackedServiceTask("calendar_course_linker", priority: .utility) {
                    await CalendarCourseLinker.shared.scanAndLink()
                }
            }
            .onChange(of: appAppearanceRaw) { _, newValue in
                applyMacAppearance(from: newValue)
            }
    }

    var body: some Scene {
        WindowGroup {
            Group {
            if !forceUITestMainUI, !AppleSiliconPlatform.isSupported {
                AppleSiliconRequiredView(report: AppleSiliconPlatform.report)
            } else if forceUITestMainUI {
                mainRoot()
            } else if isHostedUnitTest {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if canLeaveLaunchScreen {
                if shouldShowOnboarding {
                    onboardingRoot()
                } else {
                    mainRoot()
                }
            } else {
                LaunchPreloadView()
                    .environment(launchPreloadCoordinator)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.thinMaterial)
                    .onAppear {
                        if launchSplashShownAt == nil {
                            launchSplashShownAt = Date()
                        }
                    }
                    .task {
                        launchPreloadCoordinator.startIfNeeded(
                            collegePersistence: collegePersistence,
                            calendarManager: calendarManager,
                            brightspaceCoordinator: brightspaceCoordinator,
                            cloudIntegration: CloudIntegrationService.shared
                        )
                    }
            }
            }
            .frame(minWidth: 1080, minHeight: 700)
            .task(id: launchSplashShownAt) {
                guard !forceUITestMainUI else { return }
                guard let shownAt = launchSplashShownAt else { return }
                let remaining = launchSplashMinimumSeconds - Date().timeIntervalSince(shownAt)
                if remaining > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                }
                launchMinimumDisplayElapsed = true
            }
            .onChange(of: launchPreloadCoordinator.isCompleted) { _, completed in
                guard completed, !forceUITestMainUI else { return }
                guard let shownAt = launchSplashShownAt else { return }
                if Date().timeIntervalSince(shownAt) >= launchSplashMinimumSeconds {
                    launchMinimumDisplayElapsed = true
                }
            }
            .onAppear { activateForUITestsIfNeeded() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { activateForUITestsIfNeeded() }
            }
            .onChange(of: collegePersistence.isStoreLoaded) { _, loaded in
                guard loaded else { return }
                UITestPersistenceSeeder.seedMinimalPlannerDataIfNeeded()
            }
            .onChange(of: launchPreloadCoordinator.isCompleted) { _, completed in
                guard completed else { return }
                if SessionTerminationTracker.consumePendingAbruptTerminationPrompt() {
                    pendingCrashReportURL = CrashReportStore.consumePendingCrashReportURL()
                        ?? CrashReportStore.latestCrashReportURL()
                        ?? CrashReportStore.consumePendingSignalCrashReportURL()
                    if pendingCrashReportURL == nil {
                        CrashReportStore.recordAbruptTerminationNoteIfNeeded()
                        pendingCrashReportURL = CrashReportStore.latestCrashReportURL()
                            ?? CrashReportStore.consumePendingSignalCrashReportURL()
                    }
                    showSessionInterruptedAlert = true
                }
            }
            .sheet(isPresented: $showSessionInterruptedAlert) {
                SessionInterruptedSheet(
                    reportURL: pendingCrashReportURL,
                    onViewCrashLog: {
                        guard let reportURL = pendingCrashReportURL else { return }
                        CrashReportStore.open(reportURL)
                    },
                    onRevealInFinder: {
                        guard let reportURL = pendingCrashReportURL else { return }
                        CrashReportStore.revealInFinder(reportURL)
                    },
                    onCopyLogPath: {
                        guard let reportURL = pendingCrashReportURL else { return }
                        CrashReportStore.copyPathToPasteboard(reportURL)
                    }
                )
                .dismissOnOutsideClickForSheet()
            }
        }
        .windowToolbarStyle(.unified)
        .commands {
            PlannerMenuCommands()
        }
        .handlesExternalEvents(matching: ["college"])
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                DebugLogger.shared.lifecycle("scenePhase -> active")
            case .inactive:
                DebugLogger.shared.lifecycle("scenePhase -> inactive")
            case .background:
                DebugLogger.shared.lifecycle("scenePhase -> background")
            @unknown default:
                DebugLogger.shared.lifecycle("scenePhase -> unknown")
            }
            appActivity.handleScenePhase(newPhase)
        }
        .onChange(of: appActivity.isResourceThrottled) { _, throttled in
            applyInactiveServiceThrottle(throttled)
        }
        Settings {
            Group {
                if collegePersistence.isStoreLoaded {
                    MacStandaloneSettingsRoot()
                        .environmentObject(securityManager)
                        .environmentObject(calendarManager)
                        .environmentObject(collegePersistence)
                        .environmentObject(appNotifications)
                        .environment(appActivity)
                } else {
                    ProgressView(String(localized: "app.launch.loading"))
                        .controlSize(.large)
                        .frame(minWidth: 360, minHeight: 220)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.thinMaterial)
                }
            }
        }
        .defaultSize(width: SettingsMetrics.preferredWindowWidth, height: 760)
        .windowResizability(.automatic)
    }
}

private struct SessionInterruptedSheet: View {
    let reportURL: URL?
    let onViewCrashLog: () -> Void
    let onRevealInFinder: () -> Void
    let onCopyLogPath: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Previous session ended unexpectedly")
                .font(.title3.weight(.semibold))

            if let reportURL {
                Text("College did not shut down normally last time. Use View Crash Log to inspect the report, or Reveal in Finder to open its location.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Text("Latest report:\n\(reportURL.path)")
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                HStack(spacing: 8) {
                    Button("View Crash Log") {
                        onViewCrashLog()
                        dismiss()
                    }
                    Button("Reveal in Finder") {
                        onRevealInFinder()
                        dismiss()
                    }
                    Button("Copy Log Path") {
                        onCopyLogPath()
                        dismiss()
                    }
                }
            } else {
                Text("College did not shut down normally last time-for example after a force quit or system shutdown while the app was busy. Your planner data is stored on this Mac. Choose Continue to pick up where you left off.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Continue") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 520, idealWidth: 560, maxWidth: 620)
    }
}

