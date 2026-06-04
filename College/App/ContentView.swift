// ContentView.swift
// Feature: App
// Purpose: App module — ContentView.
// Data: CollegePersistence / repositories when applicable.

//
//  ContentView.swift
//  College
//
//  Created by Timothy Leung on 12/20/25.
//

import SwiftUI
import SwiftData
import os
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @EnvironmentObject private var collegePersistence: CollegePersistence
    @Environment(ModalCoordinator.self) private var modalCoordinator
    @EnvironmentObject private var appNotifications: AppNotificationCenter
    @EnvironmentObject private var securityManager: SecurityManager
    @EnvironmentObject private var calendarManager: CalendarIntegrationManager
    @EnvironmentObject private var locationPermissionService: LocationPermissionService
    @Environment(AppActivityCoordinator.self) private var appActivity
    @Environment(CalendarToolbarState.self) private var calendarToolbar
    @Environment(WebPortalToolbarState.self) private var webPortalToolbar
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("ui.reduceMotion") private var appReduceMotion: Bool = false
    @AppStorage("ui.enableBackgroundExtensionEffect") private var enableBackgroundExtensionEffect: Bool = true
    @AppStorage("onboarding.catalogSyncInFlight.v1") private var onboardingCatalogSyncInFlight = false
    private var menuBarCatalogStatus = CollegeMenuBarStatusModel.shared

    @AppStorage("appAppearance") private var appAppearanceRaw: String = AppAppearance.system.rawValue

    @State private var activePage: AppPage = .degree
    @State private var previousActivePage: AppPage = .degree
    @State private var pendingLMSConnectProviders: [String] = []

    /// Prevents heavy view construction on the *first* render after unlock.
    /// This avoids the common "post-auth white window" stall when views do expensive work during init/body.
    @State private var allowMainContent: Bool = false
    /// Defers `NavigationSplitView` until after the first run-loop turn so launch → main UI does not beachball AppKit.
    @State private var showMainNavigationShell: Bool = false
    @State private var waitingForFirstMainContentAppear: Bool = false
    @State private var unlockTransitionToken: UUID = UUID()
    @State private var bridgeDismissToken: UUID = UUID()

    @State private var mainContentDidLayout: Bool = false
    @State private var mainContentDidReportReady: Bool = false
    @State private var navigationSplitViewVisibility: NavigationSplitViewVisibility = .all
    @State private var bridgeDismissTask: Task<Void, Never>? = nil
    @State private var isAskCollegePresented = false
    @State private var askCollegeSessionID = UUID()
    @State private var catalogImportCoordinator = CatalogImportCoordinator()
    @State private var askCollegeRestorePage: AppPage?
    @State private var isCommandPalettePresented = false
    @State private var addSemesterPlan: PlannerPlan?
    @State private var toastHost = AppToastHost.shared

    @State private var hostWindow: NSWindow? = nil
    @State private var lastWindowRefreshAt: Date = .distantPast
    @State private var hasPrimedInitialWindowLayout: Bool = false
    @Namespace private var calendarEditorZoom

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

    private var addSemesterSheetPresented: Binding<Bool> {
        Binding(
            get: {
                if case .addSemester = modalCoordinator.activeModal { return true }
                return false
            },
            set: { isPresented in
                guard !isPresented else { return }
                guard case .addSemester = modalCoordinator.activeModal else { return }
                addSemesterPlan = nil
                modalCoordinator.addSemesterPreferredPlanID = nil
                modalCoordinator.activeModal = nil
            }
        )
    }

    private var calendarEventSheetPresented: Binding<Bool> {
        Binding(
            get: {
                guard let modal = modalCoordinator.activeModal else { return false }
                switch modal {
                case .addCalendarItem, .editCalendarItem:
                    return true
                default:
                    return false
                }
            },
            set: { isPresented in
                guard !isPresented else { return }
                guard let modal = modalCoordinator.activeModal else { return }
                switch modal {
                case .addCalendarItem, .editCalendarItem:
                    modalCoordinator.activeModal = nil
                default:
                    break
                }
            }
        )
    }

    @ViewBuilder
    private var modalOverlays: some View {
        ModalOverlayRouter(coordinator: modalCoordinator, activePage: $activePage)
        CalendarModalHost()
            .environment(modalCoordinator)
            .environmentObject(collegePersistence)
    }

    /// Heavy tabs mounted on first visit (avoids startup crash / stall from Settings + Assistant init).
    private static let lazyPreservedShellPages: [AppPage] = [.assistant, .settings]

    /// Primary sidebar destinations (only the active page is mounted at a time).
    private static let eagerPreservedShellPages: [AppPage] = {
        var pages: [AppPage] = [
            .degree, .academics, .calendar, .career, .brightspace, .documents, .profile
        ]
        #if DEBUG
        pages.append(.debug)
        #endif
        return pages
    }()

    @ViewBuilder
    private func pageView(for page: AppPage, isTabVisible: Bool) -> some View {
        switch page {
        case .academics:
            AcademicsView(
                activePage: $activePage,
                isInspectorPresented: $isAcademicsInspectorPresented
            )

        case .calendar:
            CalendarView(
                activePage: $activePage,
                cacheStore: calendarEventCacheStore
            )

        case .assistant:
            AIAssistantView(activePage: $activePage)

        case .career:
            CareerWorkspaceView()

        case .brightspace:
            BrightspaceView(activePage: $activePage, isTabVisible: isTabVisible)

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

        case .webShortcut:
            EmptyView()

        case .settings:
            SettingsView(activePage: $activePage)
                .environmentObject(locationPermissionService)

        #if DEBUG
        case .debug:
            IntelligenceDebugView()
        #endif
        }
    }

    /// Only the selected sidebar page is in the view tree. Keeping every visited tab mounted (opacity 0)
    /// left WKWebView, Calendar, and Documents alive and caused beachballs when exploring the app.
    @ViewBuilder
    private var preservedMainPagesLayer: some View {
        ZStack(alignment: .topLeading) {
            activeShellPageContent
                .id(activePage)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var activeShellPageContent: some View {
        switch activePage {
        case .webShortcut(let id):
            if let shortcut = WebShortcutStore.shortcutSync(id: id) {
                DeferredShellTabMount {
                    ShortcutWebHostView(
                        shortcut: shortcut,
                        coordinator: WebShortcutCoordinatorPool.coordinator(for: id),
                        activePage: $activePage,
                        isTabVisible: true
                    )
                }
            } else {
                ShortcutMissingPlaceholderView(activePage: $activePage)
            }

        default:
            if Self.eagerPreservedShellPages.contains(activePage)
                || Self.lazyPreservedShellPages.contains(activePage) {
                DeferredShellTabMount {
                    pageView(for: activePage, isTabVisible: true)
                }
            }
        }
    }

    @MainActor
    private func revealMainNavigationShellIfNeeded() async {
        guard !showMainNavigationShell else { return }
        await Task.yield()
        try? await Task.sleep(nanoseconds: 32_000_000)
        showMainNavigationShell = true
    }

    private func setActivePage(_ page: AppPage, animated: Bool) {
        if animated {
            activePage = page
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            activePage = page
        }
    }

    @State private var toolbarSearchText: String = ""
    @State private var calendarEventCacheStore = CalendarEventCacheStore()
    @State private var isAcademicsInspectorPresented = true
    @State private var isDocumentsInspectorPresented = false
    private var isCourseDashboardActive: Bool {
        if case .courseDashboard = modalCoordinator.activeModal { return true }
        return false
    }

    @ViewBuilder
    private var mainNavigationSplitView: some View {
        NavigationSplitView(columnVisibility: $navigationSplitViewVisibility) {
            SidebarView(activePage: $activePage)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
                .background(.clear)
        } detail: {
            mainNavigationSplitDetail
                .navigationTitle(mainNavigationSplitTitle)
                .toolbarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    MainWindowToolbar(
                        activePage: activePage,
                        academicsInspectorPresented: $isAcademicsInspectorPresented
                    )
                }
                .focusedSceneValue(\.activePage, activePage)
                .modifier(PortalWindowSearchModifier(activePage: activePage, searchText: $toolbarSearchText))
        }
        .navigationSplitViewStyle(.prominentDetail)
        .background(SplitViewAutosaveNameBridge(autosaveName: AutosaveNames.mainSidebarSplit))
    }

    private var mainNavigationShellPlaceholder: some View {
        ZStack {
            DesignSystem.Colors.bgMain
                .ignoresSafeArea()
            ProgressView()
                .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// macOS window toolbar title (single source — no duplicate in-content page headers).
    private var mainNavigationSplitTitle: String {
        switch activePage {
        case .settings:
            return ""
        case .webShortcut:
            let title = webPortalToolbar.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? activePage.windowChromeTitle : title
        default:
            return activePage.windowChromeTitle
        }
    }

    @ViewBuilder
    private var mainNavigationSplitDetail: some View {
        ZStack(alignment: .topLeading) {
            preservedMainPagesLayer

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

            if onboardingCatalogSyncInFlight || menuBarCatalogStatus.isCatalogImporting {
                BackgroundCatalogSyncBanner(reduceMotion: motionReduced)
                    .padding(.top, 10)
                    .padding(.horizontal, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(5)
            }

            if case let .courseDashboard(courseCode, defaultCourseName, defaultCreditsText, courseID) = modalCoordinator.activeModal {
                CourseDashboardView(
                    activePage: $activePage,
                    courseCode: courseCode,
                    defaultCourseName: defaultCourseName,
                    defaultCreditsText: defaultCreditsText,
                    courseID: courseID,
                    onClose: {
                        modalCoordinator.activeModal = nil
                        modalCoordinator.courseDashboardTaskOverlay = nil
                    }
                )
                .environmentObject(collegePersistence)
                .environment(modalCoordinator)
                .environmentObject(appNotifications)
                .environmentObject(securityManager)
                .environmentObject(calendarManager)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .transition(.opacity)
                .zIndex(20)
            }
        }
        .animation(DesignSystem.Motion.quickOrNone(reduceMotion: motionReduced), value: onboardingCatalogSyncInFlight)
        .animation(DesignSystem.Motion.quickOrNone(reduceMotion: motionReduced), value: menuBarCatalogStatus.isCatalogImporting)
        .animation(DesignSystem.Motion.quickOrNone(reduceMotion: motionReduced), value: pendingLMSConnectProviders)
        .animation(DesignSystem.Motion.standardOrNone(reduceMotion: motionReduced), value: modalCoordinator.activeModal)
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
        .opacity(1)
        .allowsHitTesting(true)
        .onChange(of: activePage) { oldPage, newPage in
            handleActivePageChanged(from: oldPage, to: newPage)
        }
    }

    @MainActor
    private func performSecurityUnlockTransition() async {
        logger.info("securityManager.isUnlocked -> \(securityManager.isUnlocked)")
        #if DEBUG
        UnlockDebugLog.log("ContentView.task: isUnlocked -> \(securityManager.isUnlocked)")
        #endif
        guard securityManager.encryptionEnabled else {
            allowMainContent = true
            waitingForFirstMainContentAppear = false
            return
        }

        guard securityManager.isUnlocked else {
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
        try? await Task.sleep(nanoseconds: 80_000_000)
        guard unlockTransitionToken == token else { return }
        showMainNavigationShell = false
        allowMainContent = true
        await revealMainNavigationShellIfNeeded()
        refreshHostingWindowIfPossible()
        #if DEBUG
        UnlockDebugTiming.markMainContentEnabled(token: token)
        UnlockDebugLog.log("ContentView.task: allowMainContent=true (token=\(token.uuidString))")
        #endif

        try? await Task.sleep(nanoseconds: 5_000_000_000)
        guard unlockTransitionToken == token else { return }
        if waitingForFirstMainContentAppear {
            logger.error("Timed out waiting for main content to appear after unlock")
            #if DEBUG
            UnlockDebugLog.log("ContentView: TIMEOUT waiting for main content appear after unlock")
            #endif
        }
    }

    private func handleScenePhaseChanged(_ newPhase: ScenePhase) {
        if newPhase == .background {
            LaunchShellPagePersistence.record(activePage)
            LLMMemoryLifecycle.shared.releaseNow()
        }
        guard newPhase == .active else { return }
        syncWindowTitleToActivePage()
        CareerSceneMaintenanceCoordinator.shared.schedule(bootstrapWorkdayBoard: false)
    }

    @ViewBuilder
    private var contentRootZStack: some View {
        ZStack {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            contentMainLayer
            contentInactiveDimLayer
            contentNotificationLayer
            contentUnlockBridgeLayer
            contentLockLayer
            modalOverlays
            contentToastLayer
            contentCommandPaletteLayer
        }
    }

    @ViewBuilder
    private var contentMainLayer: some View {
        if !securityManager.encryptionEnabled || allowMainContent {
            if showMainNavigationShell {
                mainNavigationSplitView
            } else {
                mainNavigationShellPlaceholder
            }
        }
    }

    @ViewBuilder
    private var contentInactiveDimLayer: some View {
        if appActivity.shouldApplyInactiveDim {
            Rectangle()
                .fill(Color(nsColor: .labelColor).opacity(0.08))
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .transition(.opacity)
                .zIndex(850)
        }
    }

    private var contentNotificationLayer: some View {
        AppNotificationHost()
            .environmentObject(appNotifications)
            .zIndex(500)
    }

    @ViewBuilder
    private var contentUnlockBridgeLayer: some View {
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
    }

    @ViewBuilder
    private var contentLockLayer: some View {
        if securityManager.encryptionEnabled && !securityManager.isUnlocked {
            UnlockView()
                .environmentObject(securityManager)
                .zIndex(950)
                .transition(.opacity)
        }
    }

    private var contentToastLayer: some View {
        AppToastOverlay(host: toastHost)
            .zIndex(600)
    }

    @ViewBuilder
    private var contentCommandPaletteLayer: some View {
        if isCommandPalettePresented {
            ZStack {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                AppCommandPalette(isPresented: $isCommandPalettePresented)
            }
            .zIndex(700)
        }
    }

    private func handleActivePageChanged(from oldPage: AppPage, to newPage: AppPage) {
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
        DebugLogger.shared.nav("Navigate: activePage -> \(newPage.rawValue)")
        WebShortcutCoordinatorPool.pruneToRegisteredShortcuts()
        if newPage != .degree && newPage != .documents {
            toolbarSearchText = ""
        }
        syncWindowTitleToActivePage()
    }

    var body: some View {
        contentRootWithPresentation
    }

    private var contentRootWithWindowChrome: some View {
        contentRootZStack
            .onReceive(NotificationCenter.default.publisher(for: .collegeShowCommandPalette)) { _ in
                isCommandPalettePresented = true
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
            .animation(DesignSystem.Motion.quickOrNone(reduceMotion: motionReduced), value: appActivity.shouldApplyInactiveDim)
            .background(WindowRefreshView { window in
                hostWindow = window
                if let window {
                    _ = window
                }
                configureWindowForFullSizeContent(window)
                syncWindowTitleToActivePage(window)

                guard window != nil, !hasPrimedInitialWindowLayout else { return }
                hasPrimedInitialWindowLayout = true
                DispatchQueue.main.async {
                    refreshHostingWindowIfPossible()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        refreshHostingWindowIfPossible()
                    }
                }
            })
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willEnterFullScreenNotification)) { notification in
                NavigationSplitChromeCoordinator.handleNotification(notification, targetMainWindow: hostWindow)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { notification in
                NavigationSplitChromeCoordinator.handleNotification(notification, targetMainWindow: hostWindow)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willExitFullScreenNotification)) { notification in
                NavigationSplitChromeCoordinator.handleNotification(notification, targetMainWindow: hostWindow)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { notification in
                guard let exited = notification.object as? NSWindow else { return }
                if let host = hostWindow {
                    guard exited === host || exited.windowNumber == host.windowNumber else { return }
                }
                nudgeHostingRootLayoutAfterFullscreenExit(exited)
                NavigationSplitChromeCoordinator.scheduleReapply(to: exited)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { notification in
                NavigationSplitChromeCoordinator.handleNotification(notification, targetMainWindow: hostWindow)
            }
            .task(id: securityManager.isUnlocked) {
                await performSecurityUnlockTransition()
            }
    }

    private var contentRootWithPresentation: some View {
        contentRootWithWindowChrome
            .animation(DesignSystem.Motion.standardOrNone(reduceMotion: motionReduced), value: modalCoordinator.activeModal)
        .task {
            await revealMainNavigationShellIfNeeded()
        }
        .onAppear {
            if !securityManager.encryptionEnabled {
                allowMainContent = true
            }
            DebugLogger.shared.nav("Root ContentView appeared; initial page=\(activePage.rawValue)")
            hydratePendingLMSConnectPromptIfNeeded()
            CareerSceneMaintenanceCoordinator.shared.schedule(bootstrapWorkdayBoard: true)

            syncWindowTitleToActivePage()

            #if DEBUG
            UnlockDebugLog.log("ContentView: onAppear")
            #endif
        }
        .onDisappear {
            bridgeDismissTask?.cancel()
            bridgeDismissTask = nil
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChanged(newPhase)
        }
        .sheet(isPresented: $isAskCollegePresented) {
            AIAssistantView(activePage: $activePage)
            .environmentObject(collegePersistence)
            .frame(minWidth: 520, minHeight: 640)
            .onDisappear {
                if let restore = askCollegeRestorePage {
                    setActivePage(restore, animated: false)
                }
                askCollegeRestorePage = nil
            }
        }
        .sheet(isPresented: calendarEventSheetPresented) {
            CalendarEventEditorSheet(zoomNamespace: calendarEditorZoom)
                .environment(modalCoordinator)
                .environmentObject(collegePersistence)
                .environmentObject(calendarManager)
        }
        .sheet(isPresented: addSemesterSheetPresented) {
            addSemesterSheetContent
        }
        .onReceive(NotificationCenter.default.publisher(for: .askCollegePresent)) { notification in
            askCollegeRestorePage = activePage
            if let raw = notification.userInfo?["restorePageRaw"] as? String,
               let page = AppPage(rawValue: raw) {
                askCollegeRestorePage = page
            }
            askCollegeSessionID = UUID()
            isAskCollegePresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .plannerOpenSettingsSection)) { notification in
            guard let raw = notification.userInfo?["sectionRaw"] as? String,
                  let section = SettingsNavSection.resolved(fromRaw: raw) else { return }
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            activePage = .settings
            _ = section
        }
        .onChange(of: appActivity.isAppActive) { _, isActive in
            guard isActive else { return }
            syncWindowTitleToActivePage()
            DispatchQueue.main.async {
                syncWindowTitleToActivePage()
            }
        }
        .onChange(of: modalCoordinator.activeModal) { _, new in
            if case .courseDashboard = new { return }
            modalCoordinator.courseDashboardTaskOverlay = nil
            if case .addSemester = new {
                resolveAddSemesterPlanIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .plannerOpenDocumentsForCourse)) { notification in
            let rawCode = (notification.userInfo?["courseCode"] as? String) ?? ""
            let normalized = rawCode
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            guard !normalized.isEmpty else { return }
            toolbarSearchText = normalized
            setActivePage(.documents, animated: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .plannerOpenPage)) { notification in
            guard let raw = notification.userInfo?["pageRaw"] as? String,
                  let page = AppPage(rawValue: raw)
            else { return }
            setActivePage(page, animated: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .plannerImportCatalogBundleFileURL)) { notification in
            guard let url = notification.userInfo?["url"] as? URL else { return }
            catalogImportCoordinator.handleIncomingFile(url: url)
        }
        .catalogBundleImportSheets(coordinator: catalogImportCoordinator)
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

            // Work around cases where SwiftUI view lifecycle progresses but the window doesn't repaint.
            refreshHostingWindowIfPossible()
            #if DEBUG
            UnlockDebugLog.log("ContentView: main content ready+laid out; hiding bridge")

            #endif
            bridgeDismissTask = nil
        }
    }

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
        target?.title = mainNavigationSplitTitle.isEmpty
            ? activePage.windowChromeTitle
            : mainNavigationSplitTitle
        if #available(macOS 26.0, *) {
            return
        }
        if target?.titleVisibility != .hidden {
            target?.titleVisibility = .hidden
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
    private func resolveAddSemesterPlanIfNeeded() {
        guard addSemesterPlan == nil else { return }
        if let preferredID = modalCoordinator.addSemesterPreferredPlanID,
           let preferred = collegePersistence.plans.first(where: { $0.id == preferredID }) {
            addSemesterPlan = preferred
            return
        }
        if let existing = collegePersistence.getActivePlan() ?? collegePersistence.plans.first {
            addSemesterPlan = existing
            return
        }
        let created = collegePersistence.addPlan(
            name: "My Plan",
            type: "Bachelors",
            major: collegePersistence.resolvedMajorNames().first ?? "",
            minor: collegePersistence.resolvedMinorNames().first ?? "",
            concentration: ""
        )
        collegePersistence.fetchPlans()
        collegePersistence.setActivePlan(created)
        addSemesterPlan = created
    }

    @ViewBuilder
    private var addSemesterSheetContent: some View {
        Group {
            if let planForAddSemester = addSemesterPlan {
                AddSemesterView(
                    isPresented: addSemesterSheetPresented,
                    plan: planForAddSemester
                )
                .environmentObject(collegePersistence)
                .environmentObject(appNotifications)
                .environment(modalCoordinator)
            } else {
                ProgressView()
                    .frame(width: 560, height: 320)
                    .onAppear { resolveAddSemesterPlanIfNeeded() }
            }
        }
        .dismissOnOutsideClickForSheet()
    }

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

    private func hydratePendingLMSConnectPromptIfNeeded() {
        guard pendingLMSConnectProviders.isEmpty else { return }
        let providers = UserDefaults.standard.stringArray(forKey: OnboardingPreferenceBridge.pendingLMSConnectKey) ?? []
        pendingLMSConnectProviders = providers
    }


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
                .font(DesignSystem.Fonts.main(size: 44))
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
    private var catalogStatus: CollegeMenuBarStatusModel { CollegeMenuBarStatusModel.shared }

    private var progressSubtitle: String {
        switch catalogStatus.catalog {
        case .inProgress(let title, _, _):
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty
                ? String(localized: "catalog.banner.importing", defaultValue: "Your catalog is still importing in the background.")
                : trimmed
        case .failed(let message):
            return message
        case .succeeded(let summary):
            return summary
        case .idle:
            return String(localized: "catalog.banner.importing", defaultValue: "Your catalog is still importing in the background.")
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            if reduceMotion {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
            } else {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                    .symbolEffect(.rotate, options: .repeating, value: catalogStatus.isCatalogImporting ? 1 : 0)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "catalog.banner.title", defaultValue: "Catalog Sync In Progress"))
                    .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                Text(progressSubtitle)
                    .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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
                .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Connect Your LMS")
                    .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                Text(providerText.isEmpty ? "Finish connecting your selected LMS providers." : "Continue connecting: \(providerText)")
                    .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
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

/// Configures the hosting `NSWindow` chrome synchronously the moment this view enters the
/// window hierarchy — before SwiftUI executes its first layout pass.
///
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
    var coordinator: ModalCoordinator
    @Binding var activePage: AppPage
    @EnvironmentObject private var collegePersistence: CollegePersistence
    @EnvironmentObject private var appNotifications: AppNotificationCenter
    @EnvironmentObject private var securityManager: SecurityManager
    @EnvironmentObject private var calendarManager: CalendarIntegrationManager

    @ViewBuilder
    private var courseDashboardTaskLayer: some View {
        if case .courseDashboard = coordinator.activeModal,
           let overlayKind = coordinator.courseDashboardTaskOverlay {
            switch overlayKind {
            case .add(let semesterID, let prefillCourseID):
                let repo = collegePersistence.profileRepository
                let prefillCourse = prefillCourseID.flatMap { try? repo.fetchCourse(id: $0) }
                let semesterFromID = semesterID.flatMap { collegePersistence.semester(with: $0) }
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
                    prefillCourseID: prefillCourseID,
                    presentationStyle: .fullScreenOverlay
                )
                .environmentObject(collegePersistence)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(220)
            case .edit(let taskID):
                let task = try? collegePersistence.calendarRepository.fetchPlannerTask(id: taskID)
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
                .environmentObject(collegePersistence)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .zIndex(220)
            }
        }
    }

    var body: some View {
        ZStack {
            Color.clear.allowsHitTesting(false)
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
                .environmentObject(CollegePersistence.shared)
                .environmentObject(appNotifications)
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
                .environmentObject(CollegePersistence.shared)
                .environmentObject(appNotifications)
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
                .environmentObject(CollegePersistence.shared)
                .environmentObject(appNotifications)
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
                .environmentObject(CollegePersistence.shared)
                .environmentObject(appNotifications)
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
                    .environmentObject(CollegePersistence.shared)
                    .environmentObject(appNotifications)
                    .environmentObject(securityManager)
                    .environmentObject(calendarManager)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                }
                .zIndex(200)

            case .addGenEdCourse, .addCatalogCourseGlobal, .addCatalogCourse, .assignRequirementCourse:
                EmptyView()

            case .addCalendarItem, .editCalendarItem, .addTask, .editTask:
                EmptyView()

            case .courseDashboard:
                EmptyView()

            case .addSemester:
                EmptyView()

            case .none:
                EmptyView()
            }
            courseDashboardTaskLayer
            }
        }
        .sheet(isPresented: Binding(
            get: {
                if let modal = coordinator.activeModal {
                    if case .addGenEdCourse = modal { return true }
                    if case .addCatalogCourseGlobal = modal { return true }
                    if case .addCatalogCourse = modal { return true }
                    if case .assignRequirementCourse = modal { return true }
                }
                return false
            },
            set: { isPresented in
                if !isPresented {
                    if let modal = coordinator.activeModal {
                        switch modal {
                        case .addGenEdCourse, .addCatalogCourseGlobal, .addCatalogCourse, .assignRequirementCourse:
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
                    .environmentObject(collegePersistence)
                    .dismissOnOutsideClickForSheet()
                case .addCatalogCourseGlobal(let tagAsGenEd):
                    GenEdAddCourseModal(
                        targetSemesterID: nil,
                        tagAsGenEd: tagAsGenEd
                    )
                    .environmentObject(collegePersistence)
                    .dismissOnOutsideClickForSheet()
                case .addCatalogCourse(let semesterID):
                    GenEdAddCourseModal(
                        targetSemesterID: semesterID,
                        tagAsGenEd: false
                    )
                    .environmentObject(collegePersistence)
                    .dismissOnOutsideClickForSheet()
                case .assignRequirementCourse(let assignment):
                    GenEdAddCourseModal(
                        targetSemesterID: nil,
                        tagAsGenEd: false,
                        fulfillmentAssignment: assignment
                    )
                    .environmentObject(collegePersistence)
                    .dismissOnOutsideClickForSheet()
                default:
                    EmptyView()
                        .dismissOnOutsideClickForSheet()
                }
            }
        }
    }
}

/// Shell tab mount wrapper (immediate mount; launch preload supplies data before first paint).
private struct DeferredShellTabMount<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Window-toolbar search: system `.searchable` placement on macOS (Liquid Glass).
private struct PortalWindowSearchModifier: ViewModifier {
    let activePage: AppPage
    @Binding var searchText: String

    func body(content: Content) -> some View {
        switch activePage {
        case .degree:
            content.searchable(text: $searchText, placement: .toolbar, prompt: "Search courses")
        case .documents:
            content.searchable(
                text: $searchText,
                placement: .toolbar,
                prompt: String(localized: "documents.search.placeholder", defaultValue: "Search local vault")
            )
        default:
            content
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(CollegePersistence.shared)
        .environmentObject(AppDataStore.shared)
        .environment(ModalCoordinator())
        .environmentObject(AppNotificationCenter.shared)
        .environmentObject(CalendarIntegrationManager())
        .environmentObject(LocationPermissionService())
        .environmentObject(SecurityManager.shared)
        .environment(AppActivityCoordinator.shared)
        .environment(CalendarToolbarState())
        .environment(WebPortalToolbarState())
        .environment(AcademicsToolbarState())
        .environment(CareerToolbarState())
        .environment(AuditSnapshotStore())
        .modelContainer(AppDataStore.shared.profileContainer)
}
