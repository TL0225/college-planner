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

import CollegeCalendar
import SwiftUI

import AppKit
import SwiftData

@main
struct CollegeApp: App {
    @NSApplicationDelegateAdaptor(CollegeAppDelegate.self) private var collegeAppDelegate

    @State private var appContainer = AppContainer.makeMainWindow()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboarding.completed.v1") private var onboardingCompleted: Bool = false
    @State private var showSessionInterruptedAlert = false
    @State private var pendingCrashReportURL: URL?
    @State private var launchMinimumDisplayElapsed = false
    @State private var launchSplashShownAt: Date?
    private let launchSplashMinimumSeconds: TimeInterval = 1.4
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
    private let showsMenuBarExtra = !CollegeTestRuntime.isUnitTestProcess || UITestLaunchFlags.forcesMainUI
    private var canLeaveLaunchScreen: Bool {
        forceUITestMainUI || (appContainer.launchPreloadCoordinator.isCompleted && launchMinimumDisplayElapsed)
    }

    private var usesMainShellSizing: Bool {
        if isHostedUnitTest { return false }
        if forceUITestMainUI { return true }
        return canLeaveLaunchScreen
    }

    /// XCTest snapshots were missing the main window entirely until the app was activated
    /// and key; this mirrors what a user does when clicking the dock icon.
    private func activateForUITestsIfNeeded() {
        guard forceUITestMainUI else { return }
        UITestLaunchFlags.activateMainWindowIfUITestBoot()
    }

    private var shouldShowOnboarding: Bool {
        if forceUITestMainUI { return false }
        guard appContainer.launchPreloadCoordinator.isCompleted, appContainer.persistence.isStoreLoaded else { return false }

        // Finished onboarding is stored in UserDefaults, not inferred from SQLite alone.
        if onboardingCompleted { return false }

        let noPlans = appContainer.persistence.plans.isEmpty
            && ((try? appContainer.appDataStore.profileRepository.fetchPlans(limit: 1).isEmpty) ?? true)
        let noSemesters = appContainer.persistence.semesters.isEmpty
            && ((try? appContainer.appDataStore.profileRepository.fetchSemesters(limit: 1).isEmpty) ?? true)
        guard noPlans, noSemesters else { return false }

        if hasEstablishedAcademicIdentity(in: appContainer.persistence) { return false }

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
        LMSStorageKeys.migrateLegacyDefaultsIfNeeded()
        // Initialize production logger immediately on app launch.
        // Also capture stdout/stderr so print() + runtime warnings are preserved.
        AppLogger.shared.redirectConsoleOutput()
        RuntimeTelemetryMonitor.shared.markServiceState("app", state: "initializing")
        LaunchPreloadCoordinator.bootstrapBuiltInFeaturePreloadsIfNeeded()
        CalendarPersistencePortBootstrap.wire()
        CalendarPersistencePortBootstrap.wireReadPorts()
        CalendarPersistencePortBootstrap.wireOverlays()
        CalendarPersistencePortBootstrap.wireIntegrationPorts()
        Task { @MainActor in
            await BackgroundServiceOnDemand.run(id: "model_migration") {
                ModelMigrationService.runLaunchMigrationsIfNeeded()
            }
        }

        let logger = DebugLogger.shared
        logger.app("🚀 App init")
        logger.app("Date: \(Date())")
        logger.app("Locale: \(Locale.current.identifier)")
        logger.app("TimeZone: \(TimeZone.current.identifier)")
        logger.app("ProcessInfo: \(ProcessInfo.processInfo.processName)")
        logger.app("OS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        let platform = AppleSiliconPlatform.report
        logger.app("Platform: \(platform.deviceName) — Apple Silicon supported: \(platform.isSupported), MLX compatible: \(platform.isMLXCompatible)")
        if let reason = platform.requirementMessage {
            logger.app("Platform: \(reason)")
        }
        if let mlxReason = platform.mlxRequirementMessage {
            logger.app("Platform MLX: \(mlxReason)")
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
        Task {
            if throttled {
                await BackgroundServiceRegistry.shared.pauseAll()
            } else {
                await BackgroundServiceRegistry.shared.resumeAll()
            }
        }
    }

    @ViewBuilder
    private func onboardingRoot() -> some View {
        OnboardingRootView {
            onboardingCompleted = true
            ProductAnalytics.track(.onboardingCompleted)
            if !UserDefaults.standard.bool(forKey: OnboardingPreferenceBridge.deepCatalogScrapeCompletedKey) {
                UserDefaults.standard.set(true, forKey: OnboardingPreferenceBridge.showDeepCatalogPromptKey)
            }
        }
        .appContainerEnvironment(appContainer)
        .environment(\.timeZone, selectedTimeZone)
        .environment(\.calendar, selectedCalendar)
        .environment(NetworkConnectivityMonitor.shared)
    }

    @ViewBuilder
    private func mainRoot() -> some View {
        ContentView()
            .appContainerEnvironment(appContainer)
            .environment(\.timeZone, selectedTimeZone)
            .environment(\.calendar, selectedCalendar)
            .environment(WidgetRegistry.shared)
            .environment(NetworkConnectivityMonitor.shared)
            .onOpenURL { url in
                _ = CollegeInboundURLDispatcher.handle(
                    url,
                    spotifyHandler: { _ in },
                    careerJobHandler: { appContainer.careerNavigationRouter.boardJob(id: $0) }
                )
            }
            .handlesExternalEvents(preferring: ["college"], allowing: ["*"])
            .onAppear {
                guard !isHostedUnitTest else { return }
                Task { @MainActor in
                    appContainer.academicMetricsStore.refresh()
                }
                DebugLogger.shared.lifecycle("WindowGroup ContentView appeared")
                applyInactiveServiceThrottle(appContainer.appActivity.isResourceThrottled)
                AppNotificationCenter.shared.requestPermission()

                applyMacAppearance(from: appAppearanceRaw)
                if UserDefaults.standard.bool(forKey: OnboardingPreferenceBridge.catalogSyncInFlightKey) {
                    CatalogMenuBarProgressNotifier.postInProgress(
                        fraction: 0.02,
                        title: "Finishing catalog import",
                        indeterminate: true
                    )
                }

                Task { await BackgroundServiceRegistry.shared.bootstrap(phase: .atMainUIReady) }
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
                Group {
                    if shouldShowOnboarding {
                        onboardingRoot()
                    } else {
                        mainRoot()
                    }
                }
            } else {
                launchSplashRoot()
            }
            }
            .modifier(MainWindowMinimumSizePolicy(
                isHostedUnitTest: isHostedUnitTest,
                usesMainShellSizing: usesMainShellSizing
            ))
            .onChange(of: canLeaveLaunchScreen) { _, canLeave in
                guard canLeave else { return }
                DispatchQueue.main.async {
                    guard let window = NSApp.windows.first(where: {
                        $0.styleMask.contains(.resizable) && !$0.isSheet
                    }) else { return }
                    MainWindowFramePolicy.adoptMainShellPlacementIfNeeded(window)
                }
            }
            .task(id: launchSplashShownAt) {
                guard !forceUITestMainUI else { return }
                guard let shownAt = launchSplashShownAt else { return }
                let remaining = launchSplashMinimumSeconds - Date().timeIntervalSince(shownAt)
                if remaining > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                }
                launchMinimumDisplayElapsed = true
            }
            .onChange(of: appContainer.launchPreloadCoordinator.isCompleted) { _, completed in
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
            .onChange(of: appContainer.persistence.isStoreLoaded) { _, loaded in
                guard loaded else { return }
                UITestPersistenceSeeder.seedUITestDataIfNeeded()
            }
            .onChange(of: appContainer.launchPreloadCoordinator.isCompleted) { _, completed in
                guard completed else { return }
                if let shownAt = launchSplashShownAt {
                    let durationMs = Int(Date().timeIntervalSince(shownAt) * 1000)
                    LaunchHistoryStore.recordLaunch(
                        durationMs: durationMs,
                        footprintMB: PerformanceDiagnostics.footprintMemoryMB()
                    )
                    if LaunchPerformanceAcceptance.pipelineDurationExceedsBudget(durationMs: durationMs) {
                        DiagnosticsEvent.emit(
                            subsystem: .launch,
                            severity: .warning,
                            code: "LAUNCH_SLOW",
                            message: "Launch took \(durationMs) ms."
                        )
                    }
                }
                if SessionTerminationTracker.consumePendingAbruptTerminationPrompt() {
                    DiagnosticsEvent.emit(
                        subsystem: .crash,
                        severity: .warning,
                        code: "SESSION_ABRUPT_EXIT",
                        message: "Previous session ended unexpectedly."
                    )
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
                    },
                    onContinue: {
                        showSessionInterruptedAlert = false
                    }
                )
                .dismissOnOutsideClickForSheet()
            }
        }
        .defaultSize(width: 1100, height: 760)
        .windowToolbarStyle(.unified)
        .commands {
            PlannerMenuCommands()
            InspectorCommands()
            TextEditingCommands()
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
            appContainer.appActivity.handleScenePhase(newPhase)
        }
        .onChange(of: appContainer.appActivity.isResourceThrottled) { _, throttled in
            applyInactiveServiceThrottle(throttled)
        }
        resumeBuilderScene

        WindowGroup(id: "documents-window") {
            DocumentsWindowRoot()
                .appContainerEnvironment(appContainer)
        }
        .defaultSize(width: 980, height: 720)

        WindowGroup(id: "career-apply", for: CareerApplySessionID.self) { $sessionID in
            if let sessionID {
                CareerApplyWindowRoot(sessionID: sessionID)
                    .appContainerEnvironment(appContainer)
            } else {
                ProgressView("Loading apply session…")
            }
        }
        .defaultSize(width: 1100, height: 800)
        .restorationBehavior(.disabled)

        Settings {
            Group {
                if appContainer.persistence.isStoreLoaded {
                    MacStandaloneSettingsRoot()
                    .appContainerEnvironment(appContainer)
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

        MenuBarExtra(isInserted: .constant(showsMenuBarExtra)) {
            CollegeMenuBarRoot()
                .appContainerEnvironment(appContainer)
        } label: {
            CollegeMenuBarLabel()
        }
        // Window style keeps layout in a real panel (not NSMenu rows) so live
        // background updates don't cross-wire menu item identities in Release.
        .menuBarExtraStyle(.window)
    }
    @SceneBuilder
    private var resumeBuilderScene: some Scene {
        WindowGroup(id: "resume-builder", for: UUID.self) { $documentID in
            ResumeBuilderRoot(restoringDocumentID: documentID)
                .appContainerEnvironment(appContainer)
        }
        .defaultSize(width: 1100, height: 760)
        .restorationBehavior(.disabled)
    }

    @ViewBuilder
    private func launchSplashRoot() -> some View {
        LaunchPreloadView()
            .appContainerEnvironment(appContainer)
            .onAppear {
                if launchSplashShownAt == nil {
                    launchSplashShownAt = Date()
                }
            }
            .task {
                LaunchPreloadBridge.runPipelineIfNeeded(
                    coordinator: appContainer.launchPreloadCoordinator,
                    collegePersistence: appContainer.persistence,
                    calendarManager: appContainer.calendarManager,
                    lmsCoordinator: appContainer.lmsCoordinator,
                    cloudIntegration: CloudIntegrationService.shared
                )
            }
    }
}

private struct MainWindowMinimumSizePolicy: ViewModifier {
    let isHostedUnitTest: Bool
    let usesMainShellSizing: Bool

    func body(content: Content) -> some View {
        if isHostedUnitTest {
            content.frame(minWidth: 1, minHeight: 1)
        } else if usesMainShellSizing {
            content.frame(minWidth: 820, minHeight: 600)
        } else {
            content.fixedSize()
        }
    }
}

private struct SessionInterruptedSheet: View {
    let reportURL: URL?
    let onViewCrashLog: () -> Void
    let onRevealInFinder: () -> Void
    let onCopyLogPath: () -> Void
    let onContinue: () -> Void

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
                    .padding(DesignSystem.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                HStack(spacing: 8) {
                    Button("View Crash Log") {
                        onViewCrashLog()
                        onContinue()
                    }
                    Button("Reveal in Finder") {
                        onRevealInFinder()
                        onContinue()
                    }
                    Button("Copy Log Path") {
                        onCopyLogPath()
                        onContinue()
                    }
                }
            } else {
                Text("College did not shut down normally last time—for example after a force quit or system shutdown while the app was busy. Your planner data is stored on this Mac. Choose Continue to pick up where you left off.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Continue") { onContinue() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(minWidth: 520, idealWidth: 560, maxWidth: 620)
    }
}

