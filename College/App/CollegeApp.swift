//
//  CollegeApp.swift
//  College
//
//  Created by Timothy Leung on 12/20/25.
//

import SwiftUI

#if os(macOS)
import AppKit
#endif

@main
struct CollegeApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(CollegeAppDelegate.self) private var collegeAppDelegate
    #endif

    @StateObject private var coreDataManager = CoreDataManager.shared
    @StateObject private var academicMetricsStore = AcademicMetricsStore()
    @StateObject private var modalCoordinator = ModalCoordinator()
    @StateObject private var appNotifications = AppNotificationCenter.shared
    @StateObject private var locationPermissionService = LocationPermissionService()
    @StateObject private var calendarManager = CalendarIntegrationManager()
    #if os(macOS)
    @StateObject private var appToolbarCoordinator = AppToolbarCoordinator()
    #endif
    @StateObject private var securityManager = SecurityManager.shared
    @StateObject private var brightspaceCoordinator = BrightspaceWebCoordinator()
    @StateObject private var launchPreloadCoordinator = LaunchPreloadCoordinator()
    @StateObject private var appActivity = AppActivityCoordinator.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboarding.completed.v1") private var onboardingCompleted: Bool = false
    @State private var showSessionInterruptedAlert = false
    @State private var pendingCrashReportURL: URL?
    @State private var launchMinimumDisplayElapsed = false
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
    private var canLeaveLaunchScreen: Bool {
        forceUITestMainUI || (launchPreloadCoordinator.isCompleted && launchMinimumDisplayElapsed)
    }

    #if os(macOS)
    /// XCTest snapshots were missing the main window entirely until the app was activated
    /// and key; this mirrors what a user does when clicking the dock icon.
    private func activateForUITestsIfNeeded() {
        guard forceUITestMainUI else { return }
        UITestLaunchFlags.activateMainWindowIfUITestBoot()
    }
    #endif

    private var shouldShowOnboarding: Bool {
        if forceUITestMainUI { return false }
        guard launchPreloadCoordinator.isCompleted, coreDataManager.isStoreLoaded else { return false }

        let noPlans = coreDataManager.plans.isEmpty
        let noSemesters = coreDataManager.semesters.isEmpty

        let school = (coreDataManager.profile?.collegeName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let degree = (coreDataManager.profile?.degreeLevel ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let major = (coreDataManager.profile?.major ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let missingCoreAcademicIdentity = school.isEmpty || degree.isEmpty || major.isEmpty
        let dataStateRequiresOnboarding = noPlans && noSemesters && missingCoreAcademicIdentity

        return dataStateRequiresOnboarding
    }

    init() {
        UITestLaunchFlags.applyInjectedUserDefaultsIfNeeded()
        // Initialize production logger immediately on app launch.
        // Also capture stdout/stderr so print() + runtime warnings are preserved.
        AppLogger.shared.redirectConsoleOutput()
        RuntimeTelemetryMonitor.shared.startIfNeeded()
        RuntimeTelemetryMonitor.shared.markServiceState("app", state: "initializing")
        LaunchPreloadCoordinator.bootstrapBuiltInFeaturePreloadsIfNeeded()

        // Register built-in widgets so WidgetRegistry is populated before
        // OverviewView appears. Third-party widgets can call register() here too.

        let logger = DebugLogger.shared
        logger.app("🚀 App init")
        logger.app("Date: \(Date())")
        logger.app("Locale: \(Locale.current.identifier)")
        logger.app("TimeZone: \(TimeZone.current.identifier)")
        logger.app("ProcessInfo: \(ProcessInfo.processInfo.processName)")
        logger.app("OS: \(ProcessInfo.processInfo.operatingSystemVersionString)")

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

        #if os(macOS)
        MLXGlobalErrorHandler.installIfNeeded()
        CrashReportStore.installSignalCrashCaptureIfNeeded()
        UncaughtExceptionLogger.installIfNeeded()
        CatalogMenuBarProgressController.shared.startObservingProgressNotifications()
        #endif

        RuntimeTelemetryMonitor.shared.markServiceState("app", state: "initialized")
    }

    #if os(macOS)
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
    #endif

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
        .environmentObject(coreDataManager)
        .environmentObject(launchPreloadCoordinator)
        .environment(\.managedObjectContext, coreDataManager.viewContext)
        .environment(\.timeZone, selectedTimeZone)
        .environment(\.calendar, selectedCalendar)
        .environmentObject(modalCoordinator)
        .environmentObject(appNotifications)
        .environmentObject(calendarManager)
        .environmentObject(locationPermissionService)
        .environmentObject(securityManager)
        .environmentObject(brightspaceCoordinator)
        .environmentObject(appActivity)
        #if os(macOS)
        .environmentObject(appToolbarCoordinator)
        #endif
    }

    @ViewBuilder
    private func mainRoot() -> some View {
        ContentView()
            .environmentObject(coreDataManager)
            .environmentObject(academicMetricsStore)
            .environment(\.managedObjectContext, coreDataManager.viewContext)
            .environment(\.timeZone, selectedTimeZone)
            .environment(\.calendar, selectedCalendar)
            .environmentObject(modalCoordinator)
            .environmentObject(appNotifications)
            .environmentObject(calendarManager)
            .environmentObject(locationPermissionService)
            .environmentObject(securityManager)
            .environmentObject(brightspaceCoordinator)
            .environmentObject(launchPreloadCoordinator)
            .environmentObject(appActivity)
            #if os(macOS)
            .environmentObject(appToolbarCoordinator)
            #endif
            .onOpenURL { url in
                _ = CollegeInboundURLDispatcher.handle(url) { _ in
                }
            }
            .handlesExternalEvents(preferring: ["college"], allowing: ["*"])
            .onAppear {
                academicMetricsStore.refresh()
                DebugLogger.shared.lifecycle("WindowGroup ContentView appeared")
                #if os(macOS)
                applyInactiveServiceThrottle(appActivity.isResourceThrottled)
                #endif
                AppNotificationCenter.shared.requestPermission()
                CalendarReminderScheduler.shared.registerNotificationCategories()
                CalendarReminderScheduler.shared.requestAuthorizationIfNeeded()

                #if os(macOS)
                applyMacAppearance(from: appAppearanceRaw)
                CatalogMenuBarProgressController.shared.startObservingProgressNotifications()
                if UserDefaults.standard.bool(forKey: OnboardingPreferenceBridge.catalogSyncInFlightKey) {
                    CatalogMenuBarProgressNotifier.postInProgress(
                        fraction: 0.02,
                        title: "Finishing catalog import",
                        indeterminate: true
                    )
                }
                #endif

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
                #if os(macOS)
                applyMacAppearance(from: newValue)
                #endif
            }
    }

    var body: some Scene {
        WindowGroup {
            Group {
            if forceUITestMainUI {
                mainRoot()
            } else if canLeaveLaunchScreen {
                if shouldShowOnboarding {
                    onboardingRoot()
                } else {
                    mainRoot()
                }
            } else {
                LaunchPreloadView()
                    .environmentObject(launchPreloadCoordinator)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.thinMaterial)
                    .task {
                        launchPreloadCoordinator.startIfNeeded(
                            coreDataManager: coreDataManager,
                            calendarManager: calendarManager,
                            brightspaceCoordinator: brightspaceCoordinator,
                            cloudIntegration: CloudIntegrationService.shared
                        )
                    }
            }
            }
            .frame(minWidth: 1080, minHeight: 700)
            .task {
                guard !forceUITestMainUI, !launchMinimumDisplayElapsed else { return }
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                launchMinimumDisplayElapsed = true
            }
            #if os(macOS)
            .onAppear { activateForUITestsIfNeeded() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { activateForUITestsIfNeeded() }
            }
            #endif
            .onChange(of: coreDataManager.isStoreLoaded) { _, loaded in
                guard loaded else { return }
                UITestCoreDataSeeder.seedMinimalPlannerDataIfNeeded(coreDataManager: coreDataManager)
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
                        #if os(macOS)
                        CrashReportStore.open(reportURL)
                        #endif
                    },
                    onRevealInFinder: {
                        guard let reportURL = pendingCrashReportURL else { return }
                        #if os(macOS)
                        CrashReportStore.revealInFinder(reportURL)
                        #endif
                    },
                    onCopyLogPath: {
                        guard let reportURL = pendingCrashReportURL else { return }
                        #if os(macOS)
                        CrashReportStore.copyPathToPasteboard(reportURL)
                        #endif
                    }
                )
                .dismissOnOutsideClickForSheet()
            }
        }
        #if os(macOS)
        .windowToolbarStyle(.unified)
        .commands {
            PlannerMenuCommands()
        }
        #endif
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
            #if os(macOS)
            applyInactiveServiceThrottle(throttled)
            #endif
        }
        #if os(macOS)
        Settings {
            Group {
                if coreDataManager.isStoreLoaded {
                    SettingsView(activePage: .constant(.settings))
                        .environmentObject(securityManager)
                        .environmentObject(calendarManager)
                        .environmentObject(coreDataManager)
                        .environmentObject(appNotifications)
                        .environmentObject(appActivity)
                } else {
                    ProgressView(String(localized: "app.launch.loading"))
                        .controlSize(.large)
                        .frame(minWidth: 360, minHeight: 220)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.thinMaterial)
                }
            }
        }
        .defaultSize(width: 1120, height: 760)
        .windowResizability(.automatic)
        #endif
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

