//
//  ContentView.swift
//  College
//
//  Created by Timothy Leung on 12/20/25.
//

import SwiftUI
import os
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @EnvironmentObject private var coreDataManager: CoreDataManager
    @EnvironmentObject private var modalCoordinator: ModalCoordinator
    @EnvironmentObject private var appNotifications: AppNotificationCenter
    @EnvironmentObject private var securityManager: SecurityManager
    @EnvironmentObject private var calendarManager: CalendarIntegrationManager
    @EnvironmentObject private var appActivity: AppActivityCoordinator
#if os(macOS)
    @EnvironmentObject private var toolbarCoordinator: AppToolbarCoordinator
#endif
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("ui.reduceMotion") private var appReduceMotion: Bool = false
    @AppStorage("onboarding.catalogSyncInFlight.v1") private var onboardingCatalogSyncInFlight = false

    @AppStorage("appAppearance") private var appAppearanceRaw: String = AppAppearance.system.rawValue

    @State private var activePage: AppPage = .degree
    @State private var previousActivePage: AppPage = .degree
    @State private var pendingLMSConnectProviders: [String] = []

    /// Prevents heavy view construction on the *first* render after unlock.
    /// This avoids the common "post-auth white window" stall when views do expensive work during init/body.
    @State private var allowMainContent: Bool = false
    @State private var waitingForFirstMainContentAppear: Bool = false
    @State private var unlockTransitionToken: UUID = UUID()
    @State private var bridgeDismissToken: UUID = UUID()

    @State private var mainContentDidLayout: Bool = false
    @State private var mainContentDidReportReady: Bool = false
    @State private var navigationSplitViewVisibility: NavigationSplitViewVisibility = .all
    @State private var bridgeDismissTask: Task<Void, Never>? = nil

    #if os(macOS)
    @State private var hostWindow: NSWindow? = nil
    @State private var lastWindowRefreshAt: Date = .distantPast
    @State private var hasPrimedInitialWindowLayout: Bool = false
    #endif

    private let logger = Logger(subsystem: "Timothy.College", category: "ContentView")
    private static let performanceLog = OSLog(subsystem: "Timothy.College", category: .pointsOfInterest)

    private var appAppearance: AppAppearance {
        AppAppearance(rawValue: appAppearanceRaw) ?? .system
    }

    private var rootBackgroundColor: Color {
        return DesignSystem.Colors.bgMain
    }

    private var motionReduced: Bool {
        reduceMotion || appReduceMotion
    }

    private var showLeadingSidebarToggleInSidebar: Bool {
#if os(macOS)
        navigationSplitViewVisibility != .detailOnly
#else
        false
#endif
    }

    @ViewBuilder
    private var modalOverlays: some View {
        ModalOverlayRouter(coordinator: modalCoordinator, activePage: $activePage)
    }

    @ViewBuilder
    private func pageView(for page: AppPage) -> some View {
        switch page {
        case .academics:
            AcademicsView(
                activePage: $activePage,
                isInspectorPresented: $isAcademicsInspectorPresented
            )

        case .calendar:
            CalendarView(activePage: $activePage, cacheStore: calendarEventCacheStore)

        case .assistant:
            AIAssistantView(activePage: $activePage)

        case .brightspace:
            BrightspaceView(activePage: $activePage)

        case .degree:
            OverviewView(
                activePage: $activePage,
                searchText: toolbarSearchText
            )

        case .profile:
            ProfileView(activePage: $activePage)
            
        case .documents:
            DocumentsView(
                searchText: $toolbarSearchText,
                isInspectorPresented: $isDocumentsInspectorPresented
            )

        case .webShortcut(let id):
            #if os(macOS)
            if let sc = WebShortcutStore.shortcutSync(id: id) {
                ShortcutWebHostView(
                    shortcut: sc,
                    coordinator: WebShortcutCoordinatorPool.coordinator(for: id),
                    activePage: $activePage,
                    isTabVisible: true
                )
            } else {
                Text("Shortcut unavailable")
            }
            #else
            Text("Web shortcuts are available on macOS.")
            #endif

        case .settings:
            SettingsView(activePage: $activePage)

        #if DEBUG
        case .debug:
            IntelligenceDebugView()
        #endif
        }
    }

    private func pageOrder(_ page: AppPage) -> Int {
        switch page {
        case .degree:
            return 0
        case .academics:
            return 1
        case .calendar:
            return 2
        case .assistant:
            return 3
        case .brightspace:
            return 4
        case .documents:
            return 5
        case .webShortcut:
            return 45
        case .settings:
            return 6
        case .profile:
            return 7
        #if DEBUG
        case .debug:
            return 8
        #endif
        }
    }

    private var pageSwitchTransition: AnyTransition {
        .opacity
    }

    private var pageSwitchAnimation: Animation? {
        motionReduced ? nil : .easeInOut(duration: 0.18)
    }

    @State private var toolbarSearchText: String = ""
    @State private var exportPortalDocument = PortalBackupDocument()
    @State private var isPresentingPortalExporter = false
    @State private var isPreparingPortalExport = false
    @StateObject private var calendarEventCacheStore = CalendarEventCacheStore()
    @State private var isAcademicsInspectorPresented = true
    @State private var isDocumentsInspectorPresented = false

    private var isCourseDashboardActive: Bool {
        if case .courseDashboard = modalCoordinator.activeModal { return true }
        return false
    }

    @ViewBuilder
    private var mainNavigationSplitView: some View {
        NavigationSplitView(columnVisibility: $navigationSplitViewVisibility) {
            SidebarView(
                activePage: $activePage,
                showLeadingMainSidebarToggle: showLeadingSidebarToggleInSidebar,
                onMainSidebarToggleIntent: {
                    handleMainSidebarToggleIntent()
                }
            )
            .navigationSplitViewColumnWidth(min: 214, ideal: 214, max: 214)
        } detail: {
            mainNavigationSplitDetail
        }
        #if os(macOS)
        .onChange(of: navigationSplitViewVisibility) { _, newVisibility in
            toolbarCoordinator.showsMainNavSidebarToggleInToolbar = (newVisibility == .detailOnly)
        }
        #endif
        .navigationSplitViewStyle(.balanced)
        .navigationTitle(activePage == .calendar ? "" : activePage.windowChromeTitle)
        #if os(macOS)
        .onAppear {
            toolbarCoordinator.showsMainNavSidebarToggleInToolbar =
                (navigationSplitViewVisibility == .detailOnly)
        }
        #endif
    }

    @ViewBuilder
    private var mainNavigationSplitDetail: some View {
        let isLocked = false
        ZStack(alignment: .topLeading) {
            Group {
                if activePage == .assistant {
                    // Keep Assistant state alive across tab switches.
                    pageView(for: activePage)
                } else {
                    pageView(for: activePage)
                        .id(activePage.rawValue)
                }
            }
            .transition(pageSwitchTransition)

            if !pendingLMSConnectProviders.isEmpty {
                PendingLMSConnectBanner(
                    providers: pendingLMSConnectProviders,
                    onConnectNow: {
                        openPendingLMSConnection()
                    },
                    onDismiss: {
                        dismissPendingLMSConnectPrompt()
                    }
                )
                .padding(.top, onboardingCatalogSyncInFlight ? 62 : 10)
                .padding(.horizontal, 14)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(6)
            }

            if onboardingCatalogSyncInFlight {
                BackgroundCatalogSyncBanner(reduceMotion: motionReduced)
                    .padding(.top, 10)
                    .padding(.horizontal, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(5)
            }

            if case let .courseDashboard(courseCode, defaultCourseName, defaultCreditsText, courseObjectID) = modalCoordinator.activeModal {
                CourseDashboardView(
                    activePage: $activePage,
                    courseCode: courseCode,
                    defaultCourseName: defaultCourseName,
                    defaultCreditsText: defaultCreditsText,
                    courseObjectID: courseObjectID,
                    onClose: {
                        modalCoordinator.activeModal = nil
                        modalCoordinator.courseDashboardTaskOverlay = nil
                    }
                )
                .environmentObject(coreDataManager)
                .environmentObject(modalCoordinator)
                .environmentObject(appNotifications)
                .environmentObject(securityManager)
                .environmentObject(calendarManager)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .transition(.opacity)
                .zIndex(20)
            }
        }
        .animation(pageSwitchAnimation, value: activePage)
        .animation(motionReduced ? nil : .easeInOut(duration: 0.2), value: onboardingCatalogSyncInFlight)
        .animation(motionReduced ? nil : .easeInOut(duration: 0.2), value: pendingLMSConnectProviders)
        .animation(motionReduced ? nil : .easeInOut(duration: 0.22), value: modalCoordinator.activeModal)
        .background(MainContentRenderSignal())
        // Force a full rebuild of the main content on each unlock.
        .id(unlockTransitionToken)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            logger.info("Showing main content (activePage=\(String(describing: activePage)))")
            #if DEBUG
            UnlockDebugLog.log("ContentView: showing main content (activePage=\(String(describing: activePage)))")
            #endif
        }
        .onPreferenceChange(MainContentRenderedPreferenceKey.self) { didRender in
            guard didRender else { return }
            mainContentDidLayout = true
            attemptDismissBridgeIfReady()
        }
        .onPreferenceChange(MainContentReadyPreferenceKey.self) { ready in
            guard ready else { return }
            mainContentDidReportReady = true
            attemptDismissBridgeIfReady()
        }
        .opacity(isLocked ? 0 : 1)
        .allowsHitTesting(!isLocked)
        .onChange(of: activePage) { oldPage, newPage in
            previousActivePage = oldPage
            let signpostID = OSSignpostID(log: Self.performanceLog)
            os_signpost(
                .begin,
                log: Self.performanceLog,
                name: "TabSwitch",
                signpostID: signpostID,
                "to %{public}s",
                newPage.rawValue
            )

            // Ends after the next runloop turn, approximating first-frame presentation for the selected tab.
            DispatchQueue.main.async {
                os_signpost(
                    .end,
                    log: Self.performanceLog,
                    name: "TabSwitch",
                    signpostID: signpostID,
                    "to %{public}s",
                    newPage.rawValue
                )
            }
        }
    }

    var body: some View {
        let isLocked = false

        return ZStack {
            // Placed first so `viewDidMoveToWindow` fires before any layout.
            // Non-zero frame ensures SwiftUI creates a real backing NSView.
            #if os(macOS)
            WindowChromeSetter()
                .frame(width: 1, height: 1)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            #endif

            rootBackgroundColor
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Main content layer (kept under overlays). We intentionally avoid swapping the entire
            // root between UnlockView and the main UI because that can produce a blank window on macOS.
            if !securityManager.encryptionEnabled || allowMainContent {
                mainNavigationSplitView
            }

            if appActivity.shouldApplyInactiveDim {
                Rectangle()
                    .fill(Color(nsColor: .labelColor).opacity(0.08))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transition(.opacity)
                    .zIndex(850)
            }

            // Notifications + modals should never be interactive/visible while locked.
            if !isLocked {
                AppNotificationHost()
                    .environmentObject(appNotifications)
                    .zIndex(500)
            }

            // Bridge: stays up while the main content becomes ready.
            if securityManager.encryptionEnabled && securityManager.isUnlocked && waitingForFirstMainContentAppear {
                PostUnlockBridgeView()
                    .zIndex(900)
                    .transition(.opacity)
                    .onAppear {
                        logger.info("Showing post-unlock bridge")
                        #if DEBUG
                        UnlockDebugLog.log("ContentView: showing post-unlock bridge")
                        #endif
                    }
            }

            // Lock overlay (topmost).
            if isLocked {
                UnlockView()
                    .zIndex(1000)
                    .onAppear {
                        logger.info("Showing UnlockView")
                        #if DEBUG
                        UnlockDebugLog.log("ContentView: showing UnlockView")
                        #endif
                    }
            }

            // Global overlays (modals) — only when not locked.
            modalOverlays
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(rootBackgroundColor)
        .animation(
            motionReduced ? .easeOut(duration: 0.08) : .easeInOut(duration: 0.16),
            value: appActivity.shouldApplyInactiveDim
        )
        .fileExporter(
            isPresented: $isPresentingPortalExporter,
            document: exportPortalDocument,
            contentType: .collegePortal,
            defaultFilename: "AcademicVault-\(portalTimestamp())"
        ) { result in
            switch result {
            case .success:
                appNotifications.post(kind: .success, title: "Vault Exported", message: "Encrypted .portal backup saved.")
            case .failure(let error):
                appNotifications.post(kind: .error, title: "Export Failed", message: error.localizedDescription)
            }
        }
            #if os(macOS)
            .background(WindowRefreshView { window in
                // Capture the hosting NSWindow so we can force a repaint after unlock transitions.
                hostWindow = window
                if let window {
                    toolbarCoordinator.attach(to: window)
                }
                syncToolbarCoordinatorState()
                configureWindowForFullSizeContent(window)
                syncWindowTitleToActivePage(window)
                stripToolbarItemBorders(window)

                // Prime first-launch layout so maximized windows do not require manual resize.
                guard window != nil, !hasPrimedInitialWindowLayout else { return }
                hasPrimedInitialWindowLayout = true
                DispatchQueue.main.async {
                    refreshHostingWindowIfPossible()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        refreshHostingWindowIfPossible()
                    }
                }
            })
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { notification in
                guard let exited = notification.object as? NSWindow else { return }
                if let host = hostWindow {
                    guard exited === host || exited.windowNumber == host.windowNumber else { return }
                }
                nudgeHostingRootLayoutAfterFullscreenExit(exited)
            }
            #endif
            #if !os(macOS)
            .preferredColorScheme(appAppearance.preferredColorScheme)
            #endif
            .task(id: securityManager.isUnlocked) {
                logger.info("securityManager.isUnlocked -> \(securityManager.isUnlocked)")
                #if DEBUG
                UnlockDebugLog.log("ContentView.task: isUnlocked -> \(securityManager.isUnlocked)")
                #endif

                // If encryption isn't enabled, the app shouldn't gate rendering at all.
                guard securityManager.encryptionEnabled else {
                    allowMainContent = true
                    waitingForFirstMainContentAppear = false
                    return
                }

                // When locked, hide main content immediately.
                guard securityManager.isUnlocked else {
                    // Ensure we don't re-show a full-screen modal overlay after unlocking.
                    modalCoordinator.activeModal = nil
                    modalCoordinator.courseDashboardTaskOverlay = nil
                    bridgeDismissTask?.cancel()
                    bridgeDismissTask = nil

                    unlockTransitionToken = UUID()
                    bridgeDismissToken = UUID()
                    mainContentDidLayout = false
                    mainContentDidReportReady = false
                    allowMainContent = false
                    waitingForFirstMainContentAppear = false
                    return
                }

                // Unlocked: show a lightweight bridge first, then enable main content after a frame.
                let token = UUID()
                bridgeDismissTask?.cancel()
                bridgeDismissTask = nil
                unlockTransitionToken = token
                bridgeDismissToken = UUID()
                mainContentDidLayout = false
                mainContentDidReportReady = false
                allowMainContent = false
                waitingForFirstMainContentAppear = true

                #if DEBUG
                UnlockDebugLog.log("ContentView.task: unlocked; delaying main content")
                #endif

                await Task.yield()
                try? await Task.sleep(nanoseconds: 80_000_000) // ~80ms (1-2 frames)
                guard unlockTransitionToken == token else { return }
                allowMainContent = true

                #if os(macOS)
                // Encourage AppKit to repaint immediately after unlocking.
                refreshHostingWindowIfPossible()
                #endif
                #if DEBUG
                UnlockDebugTiming.markMainContentEnabled(token: token)
                UnlockDebugLog.log("ContentView.task: allowMainContent=true (token=\(token.uuidString))")
                #endif

                // If main content never appears, keep the bridge visible and log.
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard unlockTransitionToken == token else { return }
                if waitingForFirstMainContentAppear {
                    logger.error("Timed out waiting for main content to appear after unlock")
                    #if DEBUG
                    UnlockDebugLog.log("ContentView: TIMEOUT waiting for main content appear after unlock")
                    #endif
                }
            }
        .animation(.easeInOut(duration: 0.2), value: modalCoordinator.activeModal)
        .onAppear {
            DebugLogger.shared.nav("Root ContentView appeared; initial page=\(activePage.rawValue)")
            hydratePendingLMSConnectPromptIfNeeded()

            #if os(macOS)
            syncToolbarCoordinatorState()
            syncWindowTitleToActivePage()
            stripToolbarItemBorders()
            #endif

            #if DEBUG
            UnlockDebugLog.log("ContentView: onAppear")
            #endif
        }
        .onDisappear {
            bridgeDismissTask?.cancel()
            bridgeDismissTask = nil
        }
        .onChange(of: activePage) { _, newPage in
            DebugLogger.shared.nav("Navigate: activePage -> \(newPage.rawValue)")
            #if os(macOS)
            syncToolbarCoordinatorState()
            syncWindowTitleToActivePage()
            stripToolbarItemBorders()
            #endif
        }
        .onChange(of: scenePhase) { _, newPhase in
            #if os(macOS)
            guard newPhase == .active else { return }
            syncToolbarCoordinatorState()
            syncWindowTitleToActivePage()
            stripToolbarItemBorders()
            #endif
        }
        .onChange(of: appActivity.isAppActive) { _, isActive in
            #if os(macOS)
            guard isActive else { return }
            syncToolbarCoordinatorState()
            syncWindowTitleToActivePage()
            stripToolbarItemBorders()
            DispatchQueue.main.async {
                syncWindowTitleToActivePage()
                stripToolbarItemBorders()
            }
            #endif
        }
        #if os(macOS)
        .onChange(of: mainContentDidLayout) { _, laidOut in
            guard laidOut else { return }
            DispatchQueue.main.async {
                repairToolbarPlacementAfterSplitLayoutCommit()
            }
        }
        .onChange(of: allowMainContent) { _, allowed in
            guard allowed else { return }
            DispatchQueue.main.async {
                repairToolbarPlacementAfterSplitLayoutCommit()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                repairToolbarPlacementAfterSplitLayoutCommit()
            }
        }
        #endif
        .onChange(of: modalCoordinator.activeModal) { _, new in
            if case .courseDashboard = new { return }
            modalCoordinator.courseDashboardTaskOverlay = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .plannerOpenDocumentsForCourse)) { notification in
            let rawCode = (notification.userInfo?["courseCode"] as? String) ?? ""
            let normalized = rawCode
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            guard !normalized.isEmpty else { return }
            toolbarSearchText = normalized
            activePage = .documents
        }
        .onReceive(NotificationCenter.default.publisher(for: .plannerOpenPage)) { notification in
            guard let raw = notification.userInfo?["pageRaw"] as? String,
                  let page = AppPage(rawValue: raw)
            else { return }
            activePage = page
        }
    }

    @MainActor
    private func attemptDismissBridgeIfReady() {
        guard waitingForFirstMainContentAppear else { return }
        guard mainContentDidLayout, mainContentDidReportReady else { return }

        let token = UUID()
        bridgeDismissToken = token

        bridgeDismissTask?.cancel()
        bridgeDismissTask = Task { @MainActor in
            await Task.yield()
            try? await Task.sleep(nanoseconds: 240_000_000) // ~240ms (a few frames)
            guard bridgeDismissToken == token else { return }
            guard waitingForFirstMainContentAppear else { return }
            guard mainContentDidLayout, mainContentDidReportReady else { return }
            withAnimation(.easeOut(duration: 0.14)) {
                waitingForFirstMainContentAppear = false
            }

            #if os(macOS)
            // Work around cases where SwiftUI view lifecycle progresses but the window doesn't repaint.
            refreshHostingWindowIfPossible()
            repairToolbarPlacementAfterSplitLayoutCommit()
            #endif
            #if DEBUG
            UnlockDebugLog.log("ContentView: main content ready+laid out; hiding bridge")
            #endif

            bridgeDismissTask = nil
        }
    }

    #if os(macOS)
    @MainActor
    private func configureWindowForFullSizeContent(_ window: NSWindow?) {
        guard let window else { return }

        CollegeAppDelegate.applyWindowChrome(to: window)
    }

    /// Keeps `NSWindow.title` in sync for menu/window proxies; title bar visibility is hidden so this
    /// is not duplicated in the chrome, but the value stays correct for the Window menu and debugging.
    @MainActor
    private func syncWindowTitleToActivePage(_ window: NSWindow? = nil) {
        let target = window ?? hostWindow
        target?.title = activePage.windowChromeTitle
        if target?.titleVisibility != .hidden {
            target?.titleVisibility = .hidden
        }
    }

    @MainActor
    private func stripToolbarItemBorders(_ window: NSWindow? = nil) {
        let target = window ?? hostWindow
        target?.toolbar?.items.forEach { item in
            item.isBordered = false
        }
    }

    @MainActor
    private func refreshHostingWindowIfPossible() {
        // Intentionally no-op.
        // AppKit redraw/layout nudges here caused Objective-C exceptions in some
        // page-switch transitions (Documents/Calendar). Keep this helper for call
        // site compatibility, but do not force any window/view mutation.
        _ = hostWindow
    }

    /// After leaving native fullscreen, SwiftUI can keep a stale `contentLayoutRect` so the
    /// detail column height collapses (AI Assistant transcript + composer clipped) until the
    /// user resizes. Re-applying the window frame and marking the content view dirty forces a
    /// second layout pass without touching arbitrary subviews (avoids the exceptions seen when
    /// recursively poking the hosting hierarchy during tab switches).
    @MainActor
    private func nudgeHostingRootLayoutAfterFullscreenExit(_ window: NSWindow) {
        func nudge() {
            window.contentView?.needsLayout = true
            let frame = window.frame
            window.setFrame(frame, display: true)
            window.contentView?.layoutSubtreeIfNeeded()
        }
        DispatchQueue.main.async {
            nudge()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            nudge()
        }
    }
    #endif

    private func portalTimestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return f.string(from: Date())
    }

    private func preparePortalBackupExport() {
        guard !isPreparingPortalExport else { return }
        isPreparingPortalExport = true

        Task {
            defer {
                Task { @MainActor in
                    isPreparingPortalExport = false
                }
            }

            do {
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("CollegePortal-\(UUID().uuidString).portal")
                try AppBackupManager.exportBackup(to: tempURL)
                let payload = try Data(contentsOf: tempURL)
                try? FileManager.default.removeItem(at: tempURL)

                await MainActor.run {
                    exportPortalDocument = PortalBackupDocument(payload: payload)
                    isPresentingPortalExporter = true
                }
            } catch {
                await MainActor.run {
                    _ = appNotifications.post(kind: .error, title: "Export Failed", message: error.localizedDescription)
                }
            }
        }
    }

    private func addSemesterFromToolbar() {
        modalCoordinator.activeModal = .addSemester
    }

    private func hydratePendingLMSConnectPromptIfNeeded() {
        guard pendingLMSConnectProviders.isEmpty else { return }
        let providers = UserDefaults.standard.stringArray(forKey: OnboardingPreferenceBridge.pendingLMSConnectKey) ?? []
        pendingLMSConnectProviders = providers
    }

    #if os(macOS)
    /// Re-applies sidebar toggle visibility for `AppToolbarCoordinator` **after** `NavigationSplitView` has laid out.
    /// On cold launch, `syncToolbarCoordinatorState()` can run while the split’s `columnVisibility` binding has not
    /// yet converged — `rebuildItems()` then picks up stale identifiers (toggle on trailing edge). Alt-tab activates
    /// `scenePhase` / window focus handlers that call `syncToolbarCoordinatorState()` again and masks the bug.
    @MainActor
    private func repairToolbarPlacementAfterSplitLayoutCommit() {
        syncToolbarCoordinatorState()
        toolbarCoordinator.rebuildItems()
    }

    @MainActor
    private func handleMainSidebarToggleIntent() {
        let nextVisibility: NavigationSplitViewVisibility =
            (navigationSplitViewVisibility == .detailOnly) ? .all : .detailOnly
        navigationSplitViewVisibility = nextVisibility
        toolbarCoordinator.showsMainNavSidebarToggleInToolbar = (nextVisibility == .detailOnly)
        DispatchQueue.main.async {
            repairToolbarPlacementAfterSplitLayoutCommit()
        }
    }

    private func syncToolbarCoordinatorState() {
        toolbarCoordinator.pageDidChange(activePage)
        toolbarCoordinator.showsMainNavSidebarToggleInToolbar = (navigationSplitViewVisibility == .detailOnly)
        toolbarCoordinator.onMainSidebarToggleRequested = { [self] in
            handleMainSidebarToggleIntent()
        }
        toolbarCoordinator.onNavigate = { [self] destination in
            activePage = destination
        }
        toolbarCoordinator.onAddSemester = { [self] in
            addSemesterFromToolbar()
        }
    }
    #endif

    private func dismissPendingLMSConnectPrompt() {
        pendingLMSConnectProviders = []
        UserDefaults.standard.removeObject(forKey: OnboardingPreferenceBridge.pendingLMSConnectKey)
    }

    private func openPendingLMSConnection() {
        let destination = OnboardingPreferenceBridge.preferredConnectDestination(from: pendingLMSConnectProviders)
        activePage = destination

        if destination == .brightspace {
            UserDefaults.standard.set(true, forKey: BrightspaceWebCoordinator.pendingLoadPortalKey)
        } else {
            let providerList = pendingLMSConnectProviders.joined(separator: ", ")
            let message = providerList.isEmpty
                ? "Open Settings > Integrations to finish connecting your LMS providers."
                : "Open Settings > Integrations to finish connecting: \(providerList)."
            appNotifications.post(kind: .info, title: "Continue LMS Setup", message: message)
        }
        dismissPendingLMSConnectPrompt()
    }
}

private struct ShortcutMissingPlaceholderView: View {
    @Binding var activePage: AppPage

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(String(localized: "shortcuts.removed_title", defaultValue: "This shortcut is no longer available"))
                .font(.headline)
            Text(String(localized: "shortcuts.removed_detail", defaultValue: "Add it again in Settings → Web Shortcuts, or pick another sidebar item."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button(String(localized: "shortcuts.go_overview", defaultValue: "Go to Overview")) {
                activePage = .degree
            }
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.windowBackground)
    }
}

private struct BackgroundCatalogSyncBanner: View {
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 10) {
            if reduceMotion {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .semibold))
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .symbolEffect(.rotate, options: .repeating, value: 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Catalog Sync In Progress")
                    .font(.system(size: 12, weight: .bold))
                Text("Your complete catalog is still importing in the background.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
        )
        .help("Catalog data is still being imported from onboarding")
    }
}

private struct PendingLMSConnectBanner: View {
    let providers: [String]
    let onConnectNow: () -> Void
    let onDismiss: () -> Void

    private var providerText: String {
        providers.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Connect Your LMS")
                    .font(.system(size: 12, weight: .bold))
                Text(providerText.isEmpty ? "Finish connecting your selected LMS providers." : "Continue connecting: \(providerText)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button("Not now") {
                onDismiss()
            }
            .buttonStyle(.plain)

            Button("Connect") {
                onConnectNow()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
        )
        .help("Onboarding selected LMS providers can be connected anytime")
    }
}

struct PortalBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.collegePortal] }

    var payload: Data

    init(payload: Data = Data()) {
        self.payload = payload
    }

    init(configuration: ReadConfiguration) throws {
        self.payload = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: payload)
    }
}

extension UTType {
    static var collegePortal: UTType {
        UTType(exportedAs: "com.timothy.college.portal")
    }
}

/// Configures the hosting `NSWindow` chrome synchronously the moment this view enters the
/// window hierarchy — before SwiftUI executes its first layout pass.
///
/// When a window launches in a maximised or zoomed state, `WindowRefreshView` applies
/// `fullSizeContentView` / `titlebarAppearsTransparent` asynchronously (via
/// `DispatchQueue.main.async`), which is always *after* the initial layout snapshot.
/// SwiftUI captures `contentLayoutRect` on that first pass, so the content area doesn't
/// account for the toolbar inset until the user manually resizes.
///
/// `WindowChromeSetter` uses `NSView.viewDidMoveToWindow` — which fires synchronously
/// during view-hierarchy construction, before layout — to apply the same settings in
/// time for the very first layout pass, making startup look identical to after-resize.
#if os(macOS)
private struct WindowChromeSetter: NSViewRepresentable {

    final class SetterView: NSView {
        private var hasConfigured = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
                guard !hasConfigured, let window else { return }
                hasConfigured = true
                // All NSWindow property writes happen on the main thread (AppKit guarantee).
                CollegeAppDelegate.applyWindowChrome(to: window)
        }
    }

    func makeNSView(context: Context) -> SetterView { SetterView() }
    func updateNSView(_ nsView: SetterView, context: Context) {}
}
#endif

#if os(macOS)
private struct WindowRefreshView: NSViewRepresentable {
    let onResolveWindow: (NSWindow?) -> Void

    final class Coordinator {
        var lastWindowNumber: Int? = nil
        var pendingResolvedWindow: NSWindow?
        var isResolveQueued = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func resolveWindowIfNeeded(_ window: NSWindow?, coordinator: Coordinator) {
        let windowNumber = window?.windowNumber
        guard windowNumber != coordinator.lastWindowNumber else { return }
        coordinator.lastWindowNumber = windowNumber
        coordinator.pendingResolvedWindow = window
        guard !coordinator.isResolveQueued else { return }
        coordinator.isResolveQueued = true
        DispatchQueue.main.async {
            coordinator.isResolveQueued = false
            let resolvedWindow = coordinator.pendingResolvedWindow
            onResolveWindow(resolvedWindow)
        }
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        resolveWindowIfNeeded(view.window, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        resolveWindowIfNeeded(nsView.window, coordinator: context.coordinator)
    }
}

#endif

private struct MainContentRenderedPreferenceKey: PreferenceKey {
    static let defaultValue: Bool = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

private struct MainContentRenderSignal: View {
    var body: some View {
        GeometryReader { _ in
            Color.clear
                .preference(key: MainContentRenderedPreferenceKey.self, value: true)
        }
        .allowsHitTesting(false)
    }
}

private struct PostUnlockBridgeView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
            Text("Unlocking…")
                .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textLight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.bgMain)
    }
}

private struct ModalOverlayRouter: View {
    @ObservedObject var coordinator: ModalCoordinator
    @Binding var activePage: AppPage
    @EnvironmentObject private var coreDataManager: CoreDataManager
    @EnvironmentObject private var appNotifications: AppNotificationCenter
    @EnvironmentObject private var securityManager: SecurityManager
    @EnvironmentObject private var calendarManager: CalendarIntegrationManager

    @ViewBuilder
    private var courseDashboardTaskLayer: some View {
        if case .courseDashboard = coordinator.activeModal,
           let overlayKind = coordinator.courseDashboardTaskOverlay {
            switch overlayKind {
            case .add(let semesterID, let prefillOID):
                let prefillCourse = prefillOID.flatMap { id in
                    (try? coreDataManager.viewContext.existingObject(with: id)) as? CourseEntity
                }
                let semesterFromID = semesterID.flatMap { coreDataManager.semester(with: $0) }
                let effectiveSemester = semesterFromID ?? prefillCourse?.semester
                AddTaskOverlay(
                    isPresented: Binding(
                        get: { coordinator.courseDashboardTaskOverlay != nil },
                        set: { presented in
                            if !presented { coordinator.courseDashboardTaskOverlay = nil }
                        }
                    ),
                    semester: effectiveSemester,
                    taskToEdit: nil,
                    prefillCourseID: prefillOID,
                    presentationStyle: .fullScreenOverlay
                )
                .environmentObject(coreDataManager)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(220)
            case .edit(let objectID):
                let task = (try? coreDataManager.viewContext.existingObject(with: objectID)) as? TaskEntity
                AddTaskOverlay(
                    isPresented: Binding(
                        get: { coordinator.courseDashboardTaskOverlay != nil },
                        set: { presented in
                            if !presented { coordinator.courseDashboardTaskOverlay = nil }
                        }
                    ),
                    semester: task?.semester,
                    taskToEdit: task,
                    presentationStyle: .fullScreenOverlay
                )
                .environmentObject(coreDataManager)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(220)
            }
        }
    }

    var body: some View {
        let isLocked = false
        ZStack {
            Color.clear.allowsHitTesting(false)
            if isLocked {
                EmptyView()
            } else {
            ZStack {
            switch coordinator.activeModal {
            case .addExperience:
                AddExperienceView(
                    isPresented: Binding(
                        get: {
                            if case .addExperience = coordinator.activeModal { return true }
                            return false
                        },
                        set: { isPresented in if !isPresented { coordinator.activeModal = nil } }
                    ),
                    experience: nil
                )
                .environmentObject(coreDataManager)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(100)

            case .editExperience(let experience):
                AddExperienceView(
                    isPresented: Binding(
                        get: {
                            if case .editExperience = coordinator.activeModal { return true }
                            return false
                        },
                        set: { isPresented in if !isPresented { coordinator.activeModal = nil } }
                    ),
                    experience: experience
                )
                .environmentObject(coreDataManager)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(100)

            case .addAchievement:
                AddAchievementOverlay(
                    isPresented: Binding(
                        get: {
                            if case .addAchievement = coordinator.activeModal { return true }
                            return false
                        },
                        set: { isPresented in if !isPresented { coordinator.activeModal = nil } }
                    ),
                    achievement: nil
                )
                .environmentObject(coreDataManager)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(100)

            case .editAchievement(let achievement):
                AddAchievementOverlay(
                    isPresented: Binding(
                        get: {
                            if case .editAchievement = coordinator.activeModal { return true }
                            return false
                        },
                        set: { isPresented in if !isPresented { coordinator.activeModal = nil } }
                    ),
                    achievement: achievement
                )
                .environmentObject(coreDataManager)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(100)

            case .editCourse(let selection):
                ZStack {
                    Rectangle()
                        .fill(Color.black.opacity(0.22))
                        .ignoresSafeArea()
                        .onTapGesture {
                            coordinator.activeModal = nil
                        }

                    EditCourseDetailsView(
                        courseCode: selection.courseCode,
                        defaultCourseName: selection.defaultCourseName,
                        defaultCreditsText: selection.defaultCreditsText,
                        onClose: { coordinator.activeModal = nil }
                    )
                    .environmentObject(coreDataManager)
                    .environmentObject(appNotifications)
                    .environmentObject(securityManager)
                    .environmentObject(calendarManager)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                }
                .zIndex(200)

            case .addGenEdCourse, .addCatalogCourseGlobal, .addCatalogCourse:
                EmptyView()

            case .addCalendarItem:
                if activePage == .calendar {
                    EmptyView()
                } else {
                    AddCalendarItemOverlay(
                        isPresented: Binding(
                            get: {
                                if case .addCalendarItem = coordinator.activeModal { return true }
                                return false
                            },
                            set: { isPresented in
                                if !isPresented { coordinator.activeModal = nil }
                            }
                        ),
                        semester: {
                            guard case .addCalendarItem(let semesterID, _, _, _) = coordinator.activeModal else { return nil }
                            guard let semesterID else { return nil }
                            return coreDataManager.semester(with: semesterID)
                        }(),
                        initialTitle: {
                            guard case .addCalendarItem(_, let title, _, _) = coordinator.activeModal else { return nil }
                            return title
                        }(),
                        initialStartDateTime: {
                            guard case .addCalendarItem(_, _, let start, _) = coordinator.activeModal else { return nil }
                            return start
                        }(),
                        initialEndDateTime: {
                            guard case .addCalendarItem(_, _, _, let end) = coordinator.activeModal else { return nil }
                            return end
                        }(),
                        eventToEdit: nil,
                        presentationStyle: .fullScreenOverlay
                    )
                    .environmentObject(coreDataManager)
                    .transition(.opacity)
                    .zIndex(200)
                }

            case .editCalendarItem(let objectID):
                if activePage == .calendar {
                    EmptyView()
                } else {
                    let event = (try? coreDataManager.viewContext.existingObject(with: objectID)) as? CalendarEventEntity
                    AddCalendarItemOverlay(
                        isPresented: Binding(
                            get: {
                                if case .editCalendarItem = coordinator.activeModal { return true }
                                return false
                            },
                            set: { isPresented in
                                if !isPresented { coordinator.activeModal = nil }
                            }
                        ),
                        semester: event?.semester,
                        initialStartDateTime: event?.startDate,
                        initialEndDateTime: event?.endDate,
                        eventToEdit: event
                    )
                    .environmentObject(coreDataManager)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(200)
                }

            case .addTask(let semesterID, let prefillCourseObjectID):
                let prefillCourse = prefillCourseObjectID.flatMap { id in
                    (try? coreDataManager.viewContext.existingObject(with: id)) as? CourseEntity
                }
                let semesterFromID = semesterID.flatMap { coreDataManager.semester(with: $0) }
                let effectiveSemester = semesterFromID ?? prefillCourse?.semester

                AddTaskOverlay(
                    isPresented: Binding(
                        get: {
                            if case .addTask = coordinator.activeModal { return true }
                            return false
                        },
                        set: { isPresented in
                            if !isPresented { coordinator.activeModal = nil }
                        }
                    ),
                    semester: effectiveSemester,
                    taskToEdit: nil,
                    prefillCourseID: prefillCourseObjectID,
                    presentationStyle: .fullScreenOverlay
                )
                .environmentObject(coreDataManager)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(200)

            case .editTask(let objectID):
                let task = (try? coreDataManager.viewContext.existingObject(with: objectID)) as? TaskEntity
                AddTaskOverlay(
                    isPresented: Binding(
                        get: {
                            if case .editTask = coordinator.activeModal { return true }
                            return false
                        },
                        set: { isPresented in
                            if !isPresented { coordinator.activeModal = nil }
                        }
                    ),
                    semester: task?.semester,
                    taskToEdit: task
                )
                .environmentObject(coreDataManager)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(200)

            case .courseDashboard:
                EmptyView()

            case .addSemester:
                ZStack {
                    Rectangle()
                        .fill(Color.black.opacity(0.22))
                        .ignoresSafeArea()
                        .onTapGesture {
                            coordinator.activeModal = nil
                        }

                    let planForAddSemester: PlanEntity = {
                        if let existing = coreDataManager.getActivePlan() ?? coreDataManager.plans.first {
                            return existing
                        }
                        let created = coreDataManager.addPlan(
                            name: "My Plan",
                            type: "Bachelors",
                            major: coreDataManager.profile?.major ?? "",
                            minor: coreDataManager.profile?.minor ?? "",
                            concentration: ""
                        )
                        coreDataManager.fetchPlans()
                        coreDataManager.setActivePlan(created)
                        return created
                    }()

                    AddSemesterView(
                        isPresented: Binding(
                            get: {
                                if case .addSemester = coordinator.activeModal { return true }
                                return false
                            },
                            set: { presented in
                                if !presented { coordinator.activeModal = nil }
                            }
                        ),
                        plan: planForAddSemester
                    )
                    .environmentObject(coreDataManager)
                    .environmentObject(appNotifications)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
                .zIndex(200)

            case .none:
                EmptyView()
            }
            courseDashboardTaskLayer
            }
        }
        }
        .sheet(isPresented: Binding(
            get: {
                if let modal = coordinator.activeModal {
                    if case .addGenEdCourse = modal { return true }
                    if case .addCatalogCourseGlobal = modal { return true }
                    if case .addCatalogCourse = modal { return true }
                }
                return false
            },
            set: { isPresented in
                if !isPresented {
                    if let modal = coordinator.activeModal {
                        switch modal {
                        case .addGenEdCourse, .addCatalogCourseGlobal, .addCatalogCourse:
                            coordinator.activeModal = nil
                        default: break
                        }
                    }
                }
            }
        )) {
            if let modal = coordinator.activeModal {
                switch modal {
                case .addGenEdCourse:
                    GenEdAddCourseModal(
                        targetSemesterID: nil,
                        tagAsGenEd: true
                    )
                    .environmentObject(coreDataManager)
                    .dismissOnOutsideClickForSheet()
                case .addCatalogCourseGlobal(let tagAsGenEd):
                    GenEdAddCourseModal(
                        targetSemesterID: nil,
                        tagAsGenEd: tagAsGenEd
                    )
                    .environmentObject(coreDataManager)
                    .dismissOnOutsideClickForSheet()
                case .addCatalogCourse(let semesterObjectID):
                    GenEdAddCourseModal(
                        targetSemesterID: semesterObjectID,
                        tagAsGenEd: false
                    )
                    .environmentObject(coreDataManager)
                    .dismissOnOutsideClickForSheet()
                default:
                    EmptyView()
                        .dismissOnOutsideClickForSheet()
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(CoreDataManager.shared)
        .environment(\.managedObjectContext, CoreDataManager.shared.viewContext)
        .environmentObject(ModalCoordinator())
}
