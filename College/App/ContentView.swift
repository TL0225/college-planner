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

import CollegeCalendar
import SwiftUI
import SwiftData
import os
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    @Environment(AppContainer.self) private var appContainer
    private var lmsCoordinator: LMSWebCoordinator { appContainer.lmsCoordinator }
    private var coordinator: LMSWebCoordinator { appContainer.lmsCoordinator }
    private var persistence: CollegePersistence { appContainer.persistence }
    private var collegePersistence: CollegePersistence { appContainer.persistence }
    private var appNotifications: AppNotificationCenter { appContainer.appNotifications }
    private var securityManager: SecurityManager { appContainer.securityManager }
    private var calendarManager: CalendarIntegrationManager { appContainer.calendarManager }
    private var locationPermissionService: LocationPermissionService { appContainer.locationPermissionService }
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.undoManager) private var environmentUndoManager
    @AppStorage("ui.reduceMotion") private var appReduceMotion: Bool = false

    @AppStorage("appAppearance") private var appAppearanceRaw: String = AppAppearance.system.rawValue

    @SceneStorage("app.activePage") private var sceneActivePageRaw = AppPage.degree.rawValue
    @State private var activePage: AppPage = .degree
    @State private var previousActivePage: AppPage = .degree
    @State private var pendingLMSConnectProviders: [String] = []
    @State private var pendingTermDatesImport = false
    @State private var isImportingTermDates = false
    @State private var termDatesImportStatus: AcademicCalendarImportStatus?
    @State private var termDatesImportDegraded = false

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
    @State private var bridgeDismissTask: Task<Void, Never>? = nil
    @State private var isAskCollegePresented = false
    @State private var askCollegeSessionID = UUID()
    @State private var catalogImportCoordinator = CatalogImportCoordinator()
    @State private var askCollegeRestorePage: AppPage?
    @State private var isCommandPalettePresented = false
    @State private var didSeedCrossLaunchPage = false
    @FocusState private var isShellSearchFocused: Bool
    @State private var isPrivacyOverviewPresented = false
    @State private var isDiagnosticsPresented = false
    @State private var addSemesterPlan: PlannerPlan?
    @State private var toastHost = AppToastHost.shared

    @State private var hostWindow: NSWindow? = nil
    @State private var mainSidebarColumnWidth: CGFloat = SidebarColumnLayout.fixedWidth
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
        CollegeReduceMotionGate.isReduced(accessibilityReduceMotion: reduceMotion, appReduceMotion: appReduceMotion)
    }

    private var calendarTaskSheetPresented: Binding<Bool> {
        Binding(
            get: {
                guard let modal = appContainer.modalCoordinator.activeModal else { return false }
                switch modal {
                case .addTask, .editTask:
                    return true
                default:
                    return false
                }
            },
            set: { isPresented in
                guard !isPresented else { return }
                switch appContainer.modalCoordinator.activeModal {
                case .addTask, .editTask:
                    appContainer.modalCoordinator.activeModal = nil
                default:
                    break
                }
            }
        )
    }

    @ViewBuilder
    private var calendarTaskSheetContent: some View {
        switch appContainer.modalCoordinator.activeModal {
        case .addTask(let semesterID, let prefillCourseID):
            let repo = appContainer.persistence.profileRepository
            let prefillCourse = prefillCourseID.flatMap { try? repo.fetchCourse(id: $0) }
            let semesterFromID = semesterID.flatMap { appContainer.persistence.semester(with: $0) }
            let effectiveSemester = semesterFromID ?? prefillCourse?.semester
            AddTaskOverlay(
                isPresented: calendarTaskSheetPresented,
                semester: effectiveSemester,
                taskToEdit: nil,
                prefillCourseID: prefillCourseID,
                presentationStyle: .anchoredPanel
            )
        case .editTask(let taskID):
            let task = try? appContainer.persistence.calendarRepository.fetchPlannerTask(id: taskID)
            AddTaskOverlay(
                isPresented: calendarTaskSheetPresented,
                semester: task?.semester,
                taskToEdit: task,
                presentationStyle: .anchoredPanel
            )
        default:
            EmptyView()
        }
    }

    private var editCourseSheetPresented: Binding<Bool> {
        Binding(
            get: {
                if case .editCourse = appContainer.modalCoordinator.activeModal { return true }
                return false
            },
            set: { isPresented in
                guard !isPresented else { return }
                if case .editCourse = appContainer.modalCoordinator.activeModal {
                    appContainer.modalCoordinator.activeModal = nil
                }
            }
        )
    }

    @ViewBuilder
    private var editCourseSheetContent: some View {
        if case .editCourse(let selection) = appContainer.modalCoordinator.activeModal {
            EditCourseDetailsView(
                courseCode: selection.courseCode,
                defaultCourseName: selection.defaultCourseName,
                defaultCreditsText: selection.defaultCreditsText,
                onClose: { appContainer.modalCoordinator.activeModal = nil }
            )
        }
    }

    private var courseDashboardTaskSheetPresented: Binding<Bool> {
        Binding(
            get: { appContainer.modalCoordinator.courseDashboardTaskOverlay != nil },
            set: { isPresented in
                if !isPresented {
                    appContainer.modalCoordinator.courseDashboardTaskOverlay = nil
                }
            }
        )
    }

    @ViewBuilder
    private var courseDashboardTaskSheetContent: some View {
        if let overlayKind = appContainer.modalCoordinator.courseDashboardTaskOverlay {
            switch overlayKind {
            case .add(let semesterID, let prefillCourseID):
                let repo = appContainer.persistence.profileRepository
                let prefillCourse = prefillCourseID.flatMap { try? repo.fetchCourse(id: $0) }
                let semesterFromID = semesterID.flatMap { appContainer.persistence.semester(with: $0) }
                let effectiveSemester = semesterFromID ?? prefillCourse?.semester
                AddTaskOverlay(
                    isPresented: courseDashboardTaskSheetPresented,
                    semester: effectiveSemester,
                    taskToEdit: nil,
                    prefillCourseID: prefillCourseID,
                    presentationStyle: .anchoredPanel
                )
            case .edit(let taskID):
                let task = try? appContainer.persistence.calendarRepository.fetchPlannerTask(id: taskID)
                AddTaskOverlay(
                    isPresented: courseDashboardTaskSheetPresented,
                    semester: task?.semester,
                    taskToEdit: task,
                    presentationStyle: .anchoredPanel
                )
            }
        }
    }

    private var addSemesterSheetPresented: Binding<Bool> {
        Binding(
            get: {
                if case .addSemester = appContainer.modalCoordinator.activeModal { return true }
                return false
            },
            set: { isPresented in
                guard !isPresented else { return }
                guard case .addSemester = appContainer.modalCoordinator.activeModal else { return }
                addSemesterPlan = nil
                appContainer.modalCoordinator.addSemesterPreferredPlanID = nil
                appContainer.modalCoordinator.activeModal = nil
            }
        )
    }

    private var calendarEventSheetPresented: Binding<Bool> {
        Binding(
            get: {
                guard let modal = appContainer.modalCoordinator.activeModal else { return false }
                switch modal {
                case .addCalendarItem, .editCalendarItem:
                    return true
                default:
                    return false
                }
            },
            set: { isPresented in
                guard !isPresented else { return }
                guard let modal = appContainer.modalCoordinator.activeModal else { return }
                switch modal {
                case .addCalendarItem, .editCalendarItem:
                    appContainer.modalCoordinator.activeModal = nil
                default:
                    break
                }
            }
        )
    }

    @ViewBuilder
    private var modalOverlays: some View {
        ModalOverlayRouter(coordinator: appContainer.modalCoordinator)
    }

    /// Heavy tabs mounted on first visit (avoids startup crash / stall from Assistant init).
    private static let lazyPreservedShellPages: [AppPage] = [.assistant]

    /// Primary sidebar destinations (only the active page is mounted at a time).
    private static let eagerPreservedShellPages: [AppPage] = {
        var pages: [AppPage] = [
            .degree, .academics, .transferDatabase, .calendar, .career, .lms, .documents, .profile
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

        case .transferDatabase:
            TransferDatabaseView(activePage: $activePage)

        case .calendar:
            CalendarView(
                isCalendarPageActive: .constant(true),
                cacheStore: calendarEventCacheStore
            )
            .calendarPackageEnvironment(
                integrationManager: appContainer.calendarManager,
                sceneState: appContainer.calendarScene
            )
            .onAppear {
                CalendarPersistencePortBootstrap.wireShell(container: appContainer)
            }

        case .assistant:
            AIAssistantView(activePage: $activePage)

        case .career:
            CareerWorkspaceView()

        case .lms:
            LMSView(activePage: $activePage, isTabVisible: isTabVisible)

        case .degree:
            OverviewView(activePage: $activePage)

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
            EmptyView()

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
                // Distinct identity per page forces the NavigationSplitView detail
                // subtree to rebuild on navigation. Without it, the detail silently
                // fails to update on some selection changes (FB/known SwiftUI bug),
                // which left Overview and Documents stuck on the prior page.
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
        if case .courseDashboard = appContainer.modalCoordinator.activeModal { return true }
        return false
    }

    @ViewBuilder
    private var mainNavigationSplitView: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SidebarView(activePage: $activePage, columnWidth: mainSidebarColumnWidth)
                .navigationSplitViewColumnWidth(
                    min: mainSidebarColumnWidth,
                    ideal: mainSidebarColumnWidth,
                    max: mainSidebarColumnWidth
                )
                .background(.clear)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Sidebar navigation")
        } detail: {
            mainNavigationSplitDetail
                .navigationTitle(mainNavigationSplitTitle)
                .navigationSubtitle(mainNavigationSplitSubtitle)
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    MainWindowToolbar(
                        activePage: activePage,
                        academicsInspectorPresented: $isAcademicsInspectorPresented,
                        documentsSearchText: $toolbarSearchText
                    )
                }
                .modifier(
                    ShellToolbarSearchModifier(
                        activePage: activePage,
                        searchText: $toolbarSearchText,
                        isSearchFocused: $isShellSearchFocused,
                        calendarScene: appContainer.calendarScene
                    )
                )
                .focusedSceneValue(\.activePage, activePage)
        }
        .navigationSplitViewStyle(.prominentDetail)
        .background(
            SplitViewAutosaveNameBridge(
                autosaveName: AutosaveNames.mainSidebarSplit,
                resolvedColumnWidth: $mainSidebarColumnWidth
            )
        )
        .onReceive(
            NotificationCenter.default.publisher(for: MainSidebarSplitAutosave.columnWidthDidResolveNotification)
        ) { notification in
            guard let width = notification.userInfo?["width"] as? CGFloat else { return }
            guard abs(mainSidebarColumnWidth - width) > 0.5 else { return }
            mainSidebarColumnWidth = width
        }
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
        case .webShortcut:
            let title = appContainer.webPortalScene.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? activePage.windowChromeTitle : title
        default:
            return activePage.windowChromeTitle
        }
    }

    /// Native window subtitle. While a course page is open on Academics, the open course
    /// code is shown as the system subtitle (e.g. title "Academics", subtitle "INFA 754")
    /// instead of a custom toolbar breadcrumb.
    private var mainNavigationSplitSubtitle: String {
        guard activePage == .academics,
              case let .courseDashboard(courseCode, _, _, _) = appContainer.modalCoordinator.activeModal
        else { return "" }
        return courseCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private let bannerStackTopPadding: CGFloat = 10

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
                .padding(.top, bannerStackTopPadding)
                .padding(.horizontal, 14)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(6)
            }

            if pendingTermDatesImport {
                PendingTermDatesImportBanner(
                    isImporting: isImportingTermDates,
                    importStatus: termDatesImportStatus,
                    isDegradedProfile: termDatesImportDegraded,
                    onImportNow: {
                        Task { await importPendingTermDates() }
                    },
                    onOpenSettings: {
                        openTermDatesSettings()
                    },
                    onDismiss: {
                        dismissPendingTermDatesImportPrompt()
                    }
                )
                .padding(.top, bannerStackTopPadding + (pendingLMSConnectProviders.isEmpty ? 0 : 54))
                .padding(.horizontal, 14)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(6)
            }

            if case let .courseDashboard(courseCode, defaultCourseName, defaultCreditsText, courseID) = appContainer.modalCoordinator.activeModal {
                CourseDashboardView(
                    activePage: $activePage,
                    courseCode: courseCode,
                    defaultCourseName: defaultCourseName,
                    defaultCreditsText: defaultCreditsText,
                    courseID: courseID,
                    onClose: {
                        appContainer.modalCoordinator.activeModal = nil
                        appContainer.modalCoordinator.courseDashboardTaskOverlay = nil
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .transition(.opacity)
                .zIndex(20)
            }
        }
        .animation(DesignSystem.Motion.quickOrNone(reduceMotion: motionReduced), value: pendingLMSConnectProviders)
        .animation(DesignSystem.Motion.quickOrNone(reduceMotion: motionReduced), value: pendingTermDatesImport)
        .animation(DesignSystem.Motion.standardOrNone(reduceMotion: motionReduced), value: appContainer.modalCoordinator.activeModal)
        .background(MainContentRenderSignal())
        // Force a full rebuild of the main content on each unlock.
        .id(unlockTransitionToken)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Main content")
        .accessibilityIdentifier("shell.mainContent")
        .shellDynamicTypeReadable()
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
            sceneActivePageRaw = newPage.rawValue
            handleActivePageChanged(from: oldPage, to: newPage)
            ProductAnalytics.track(.pageVisited, properties: ["page": newPage.rawValue])
        }
        .onAppear {
            seedActivePageFromPersistenceIfNeeded()
        }
    }

    private func seedActivePageFromPersistenceIfNeeded() {
        guard !didSeedCrossLaunchPage else { return }
        didSeedCrossLaunchPage = true
        if let persisted = LaunchShellPagePersistence.restoredPage() {
            setActivePage(persisted, animated: false)
            sceneActivePageRaw = persisted.rawValue
        } else if let restored = AppPage(rawValue: sceneActivePageRaw) {
            activePage = restored
        }
    }

    private func toggleInspectorForActivePage() {
        ShellPerformanceTiming.begin(.inspectorToggle)
        switch activePage {
        case .documents:
            isDocumentsInspectorPresented.toggle()
        case .academics:
            appContainer.toolbarDispatcher.dispatch(.academics(.statsSidebarToggle))
        case .calendar:
            appContainer.toolbarDispatcher.dispatch(.calendar(.sidebarToggle))
        case .career:
            NotificationCenter.default.post(name: .collegeCareerToggleInspector, object: nil)
        default:
            break
        }
        DispatchQueue.main.async {
            _ = ShellPerformanceTiming.end(.inspectorToggle, detail: activePage.rawValue)
        }
    }

    private func focusShellSearchField() {
        ShellPerformanceTiming.begin(.searchFocus)
        switch activePage {
        case .documents, .calendar, .academics, .career, .transferDatabase:
            isShellSearchFocused = true
            DispatchQueue.main.async {
                _ = ShellPerformanceTiming.end(.searchFocus, detail: activePage.rawValue)
            }
        default:
            isCommandPalettePresented = true
        }
    }

    private func handleIncomingFileDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let droppedURL = item as? URL {
                url = droppedURL
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let string = item as? String {
                url = URL(fileURLWithPath: string)
            } else {
                url = nil
            }
            guard let url else { return }
            Task { @MainActor in
                routeDroppedFileURL(url)
            }
        }
        return true
    }

    @MainActor
    private func routeDroppedFileURL(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "portal", "collegebackup":
            AppFileMenuActions.importBackup(from: url)
        case CatalogBundle.fileExtension:
            AppTypedNavigationRouter.importCatalogBundle(at: url)
        default:
            if ext == "sqlite", url.lastPathComponent.lowercased().hasSuffix(".collegecatalog.sqlite") {
                AppTypedNavigationRouter.importCatalogBundle(at: url)
            }
        }
    }

    @MainActor
    private func performSecurityUnlockTransition() async {
        logger.info("securityManager.isUnlocked -> \(securityManager.isUnlocked)")
        #if DEBUG
        UnlockDebugLog.log("ContentView.task: isUnlocked -> \(securityManager.isUnlocked)")
        #endif
        guard securityManager.encryptionEnabled else {
            securityManager.ensureBackupKeyIfNeeded()
            allowMainContent = true
            waitingForFirstMainContentAppear = false
            showMainNavigationShell = true
            return
        }

        guard securityManager.isUnlocked else {
            appContainer.modalCoordinator.activeModal = nil
            appContainer.modalCoordinator.courseDashboardTaskOverlay = nil
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
            // Unload shortcut web pages (including the active one) while the app is hidden.
            WebShortcutCoordinatorPool.deactivate()
        }
        guard newPhase == .active else { return }
        // Re-wake the on-screen shortcut page when the app returns to the foreground.
        if case .webShortcut(let id) = activePage {
            WebShortcutCoordinatorPool.activate(id)
        }
        syncWindowTitleToActivePage()
    }

    private func activateBackgroundServicesForPageIfNeeded(_ page: AppPage) {
        switch page {
        case .career, .calendar, .assistant, .transferDatabase:
            Task { await BackgroundServiceRegistry.shared.sceneActivated(page) }
        default:
            break
        }
    }

    @ViewBuilder
    private var contentRootZStack: some View {
        StoreOpenErrorGate(store: appContainer.appDataStore) {
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
            }
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
        if appContainer.appActivity.shouldApplyInactiveDim {
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
                .zIndex(950)
                .transition(.opacity)
        }
    }

    private var contentToastLayer: some View {
        AppToastOverlay(host: toastHost)
            .zIndex(600)
    }

    private func handleActivePageChanged(from oldPage: AppPage, to newPage: AppPage) {
        if newPage == .lms, !LMSPortalConfiguration.isLMSTabEnabled() {
            activePage = .degree
            return
        }
        previousActivePage = oldPage
        ShellPerformanceTiming.begin(.pageSwitch)
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
            _ = ShellPerformanceTiming.end(.pageSwitch, detail: "\(oldPage.rawValue)→\(newPage.rawValue)")
        }
        DebugLogger.shared.nav("Navigate: activePage -> \(newPage.rawValue)")
        WebShortcutCoordinatorPool.pruneToRegisteredShortcuts()
        // Leaving shortcuts for a non-web page: sleep all shortcut pages so none stay
        // resident off screen. Shortcut→shortcut wake/sleep is handled by the host view.
        if case .webShortcut = newPage {} else {
            WebShortcutCoordinatorPool.deactivate()
        }
        if newPage != .documents {
            toolbarSearchText = ""
        }
        syncWindowTitleToActivePage()
        activateBackgroundServicesForPageIfNeeded(newPage)
    }

    var body: some View {
        TranslationHost {
            contentRootWithPresentation
        }
    }

    private var contentRootWithWindowChrome: some View {
        contentRootWithShellMenuHandlers
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
            .animation(DesignSystem.Motion.quickOrNone(reduceMotion: motionReduced), value: appContainer.appActivity.shouldApplyInactiveDim)
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
                    NavigationSplitChromeCoordinator.scheduleReapply(to: hostWindow)
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

    private var contentRootWithShellMenuHandlers: some View {
        contentRootZStack
            .onReceive(NotificationCenter.default.publisher(for: .collegeShowCommandPalette)) { _ in
                isCommandPalettePresented = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .collegeToggleInspector)) { _ in
                toggleInspectorForActivePage()
            }
            .onReceive(NotificationCenter.default.publisher(for: .collegeFocusSearch)) { _ in
                focusShellSearchField()
            }
            .onReceive(NotificationCenter.default.publisher(for: .collegeShowPrivacyOverview)) { _ in
                isPrivacyOverviewPresented = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .collegeShowDiagnostics)) { _ in
                isDiagnosticsPresented = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .plannerImportPortalBackupFileURL)) { notification in
                guard let url = notification.userInfo?["url"] as? URL else { return }
                AppFileMenuActions.importBackup(from: url)
            }
            .onReceive(NotificationCenter.default.publisher(for: .collegeOpenDocumentsWindow)) { _ in
                openWindow(id: "documents-window")
            }
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleIncomingFileDrop(providers)
            }
    }

    private var contentRootWithPresentation: some View {
        contentRootWithShellSheets
    }

    private var contentRootWithLifecycle: some View {
        contentRootWithWindowChrome
            .animation(DesignSystem.Motion.standardOrNone(reduceMotion: motionReduced), value: appContainer.modalCoordinator.activeModal)
            .task {
                await revealMainNavigationShellIfNeeded()
            }
            .onAppear {
                seedActivePageFromPersistenceIfNeeded()
                if !securityManager.encryptionEnabled {
                    securityManager.ensureBackupKeyIfNeeded()
                    allowMainContent = true
                    showMainNavigationShell = true
                }
                DebugLogger.shared.nav("Root ContentView appeared; initial page=\(activePage.rawValue)")
                hydratePendingLMSConnectPromptIfNeeded()
                hydratePendingTermDatesImportPromptIfNeeded()
                activateBackgroundServicesForPageIfNeeded(activePage)

                syncWindowTitleToActivePage()

                #if DEBUG
                UnlockDebugLog.log("ContentView: onAppear")
                #endif
            }
            .onReceive(NotificationCenter.default.publisher(for: .academicCalendarConfigsDidChange)) { _ in
                AcademicCalendarIntegration.syncAllRegistrations(calendarManager: calendarManager)
            }
            .onReceive(NotificationCenter.default.publisher(for: .academicCalendarImportPromptScheduled)) { _ in
                hydratePendingTermDatesImportPromptIfNeeded()
            }
            .onDisappear {
                bridgeDismissTask?.cancel()
                bridgeDismissTask = nil
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChanged(newPhase)
            }
    }

    private var contentRootWithShellSheets: some View {
        contentRootWithLifecycle
        .sheet(isPresented: $isAskCollegePresented) {
            AIAssistantView(activePage: $activePage)
                .appContainerEnvironment(appContainer)
            .frame(minWidth: 520, idealWidth: 640, minHeight: 540, idealHeight: 640)
            .onDisappear {
                if let restore = askCollegeRestorePage {
                    setActivePage(restore, animated: false)
                }
                askCollegeRestorePage = nil
            }
        }
        .sheet(isPresented: $isCommandPalettePresented) {
            AppCommandPalette(isPresented: $isCommandPalettePresented)
                .dismissOnOutsideClickForSheet()
        }
        .sheet(isPresented: addSemesterSheetPresented) {
            addSemesterSheetContent
        }
        .sheet(isPresented: calendarEventSheetPresented) {
            CalendarEventEditorSheet(zoomNamespace: calendarEditorZoom)
                .appContainerEnvironment(appContainer)
        }
        .sheet(isPresented: calendarTaskSheetPresented) {
            calendarTaskSheetContent
                .frame(minWidth: 520, idealWidth: 640, minHeight: 480, idealHeight: 560)
        }
        .sheet(isPresented: editCourseSheetPresented) {
            editCourseSheetContent
                .frame(minWidth: 520, idealWidth: 640, minHeight: 480, idealHeight: 640)
        }
        .sheet(isPresented: courseDashboardTaskSheetPresented) {
            courseDashboardTaskSheetContent
                .frame(minWidth: 520, idealWidth: 640, minHeight: 480, idealHeight: 560)
        }
        .sheet(isPresented: $isPrivacyOverviewPresented) {
            PrivacyOverviewView()
                .frame(minWidth: 520, minHeight: 420)
        }
        #if DEBUG
        .sheet(isPresented: $isDiagnosticsPresented) {
            DiagnosticsCenterView()
                .appContainerEnvironment(appContainer)
                .frame(minWidth: 720, minHeight: 520)
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: .askCollegePresent)) { notification in
            askCollegeRestorePage = activePage
            if let raw = notification.userInfo?["restorePageRaw"] as? String,
               let page = AppPage(rawValue: raw) {
                askCollegeRestorePage = page
            }
            askCollegeSessionID = UUID()
            isAskCollegePresented = true
        }
        .onChange(of: appContainer.appActivity.isAppActive) { _, isActive in
            guard isActive else { return }
            syncWindowTitleToActivePage()
            DispatchQueue.main.async {
                syncWindowTitleToActivePage()
            }
        }
        .onChange(of: appContainer.modalCoordinator.activeModal) { _, new in
            if case .courseDashboard = new { return }
            appContainer.modalCoordinator.courseDashboardTaskOverlay = nil
            if case .addSemester = new {
                resolveAddSemesterPlanIfNeeded()
            }
        }
        .onReceive(AppTypedNavigationRouter.publisher) { notification in
            guard let action = AppTypedNavigationRouter.action(from: notification) else { return }
            ContentViewShellCoordinator.applyNavigation(
                action: action,
                setToolbarSearchText: { toolbarSearchText = $0 },
                openPage: { setActivePage($0, animated: false) },
                catalogImportCoordinator: catalogImportCoordinator
            )
        }
        .onAppear {
            AppUndoCoordinator.shared.connect(environmentUndoManager)
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
        MainWindowFramePolicy.adoptMainShellPlacementIfNeeded(window)
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
            if target?.titleVisibility != .visible {
                target?.titleVisibility = .visible
            }
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
        if let preferredID = appContainer.modalCoordinator.addSemesterPreferredPlanID,
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

    private func hydratePendingTermDatesImportPromptIfNeeded() {
        pendingTermDatesImport = AcademicCalendarImportPromptBridge.isPending
        if let profile = AcademicCalendarProgramProfile.resolve(persistence: collegePersistence) {
            termDatesImportDegraded = profile.isDegraded
        }
        if let schoolID = collegePersistence.getActiveUniversityName().flatMap({ name in
            SchoolManifestCatalog.bundled().first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.id
        }) {
            termDatesImportStatus = AcademicCalendarStore.primaryConfig(for: schoolID)?.importStatus
        }
    }

    private func dismissPendingTermDatesImportPrompt() {
        pendingTermDatesImport = false
        AcademicCalendarImportPromptBridge.clearPending()
    }

    private func openTermDatesSettings() {
        _ = AskCollegeCoordinator.openSettingsSection(.calendar)
        dismissPendingTermDatesImportPrompt()
    }

    @MainActor
    private func importPendingTermDates() async {
        guard !isImportingTermDates else { return }
        isImportingTermDates = true
        defer { isImportingTermDates = false }

        if let output = await AcademicCalendarImportCoordinator.importTermDates(
            persistence: collegePersistence,
            calendarManager: calendarManager,
            writeChanges: true
        ) {
            if output.needsHubPicker {
                _ = AskCollegeCoordinator.openSettingsSection(.calendar)
                appNotifications.post(
                    kind: .info,
                    title: String(localized: "calendar.term_dates.hub_title", defaultValue: "Choose Term Calendar"),
                    message: String(
                        localized: "calendar.term_dates.hub_body",
                        defaultValue: "Your school lists multiple calendars. Pick the one that matches your program in Settings → Calendar."
                    ),
                    isDismissible: true,
                    autoDismissAfter: 10
                )
            } else if let error = output.result.error ?? output.config.lastError, !error.isEmpty {
                appNotifications.post(kind: .error, title: "Term Dates Import Failed", message: error, isDismissible: true)
            } else if !output.result.parsedEvents.isEmpty {
                appNotifications.post(
                    kind: .success,
                    title: String(localized: "calendar.term_dates.import_success_title", defaultValue: "Term Dates Imported"),
                    message: String(
                        format: String(
                            localized: "calendar.term_dates.import_success_body_fmt",
                            defaultValue: "Added %d academic calendar events for your active term."
                        ),
                        output.result.parsedEvents.count
                    ),
                    isDismissible: true,
                    autoDismissAfter: 8
                )
                dismissPendingTermDatesImportPrompt()
            }
        } else {
            _ = AskCollegeCoordinator.openSettingsSection(.calendar)
            appNotifications.post(
                kind: .info,
                title: String(localized: "calendar.term_dates.setup_title", defaultValue: "Set Up Term Dates"),
                message: String(
                    localized: "calendar.term_dates.setup_body",
                    defaultValue: "Add your school calendar page URL in Settings → Calendar to import registration deadlines and breaks."
                ),
                isDismissible: true,
                autoDismissAfter: 10
            )
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

        if destination == .lms {
            UserDefaults.standard.set(true, forKey: LMSWebCoordinator.pendingLoadPortalKey)
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

private struct PendingTermDatesImportBanner: View {
    let isImporting: Bool
    let importStatus: AcademicCalendarImportStatus?
    let isDegradedProfile: Bool
    let onImportNow: () -> Void
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isImporting ? "hourglass" : "calendar.badge.plus")
                .font(DesignSystem.Fonts.main(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(AcademicCalendarStatusCopy.bannerTitle(for: importStatus))
                    .font(DesignSystem.Fonts.main(size: 12, weight: .bold))
                Text(AcademicCalendarStatusCopy.bannerSubtitle(
                    status: importStatus,
                    departmentName: nil,
                    isDegraded: isDegradedProfile
                ))
                .font(DesignSystem.Fonts.main(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                Text(AcademicCalendarStatusCopy.honestyFooter())
                    .font(DesignSystem.Fonts.main(size: 10, weight: .regular))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            Button(String(localized: "calendar.term_dates.prompt_not_now", defaultValue: "Not now")) {
                onDismiss()
            }
            .buttonStyle(.plain)

            Button(String(localized: "calendar.term_dates.prompt_settings", defaultValue: "Settings")) {
                onOpenSettings()
            }
            .buttonStyle(.bordered)

            Button(isImporting
                ? String(localized: "calendar.term_dates.prompt_importing", defaultValue: "Importing…")
                : String(localized: "calendar.term_dates.prompt_import", defaultValue: "Import")) {
                onImportNow()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isImporting)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
        )
        .help("Import term dates matched to your program catalog")
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

    func makeNSView(context: Context) -> WindowResolveHostView {
        let view = WindowResolveHostView()
        view.onResolve = onResolveWindow
        return view
    }

    func updateNSView(_ nsView: WindowResolveHostView, context: Context) {
        nsView.onResolve = onResolveWindow
    }
}

final class WindowResolveHostView: NSView {
    var onResolve: ((NSWindow?) -> Void)?
    private var lastWindowNumber: Int?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        let callback = onResolve
        DispatchQueue.main.async {
            callback?(self.window)
        }
    }

    func resolveNow() {
        let resolved = window
        let number = resolved?.windowNumber
        guard number != lastWindowNumber else { return }
        lastWindowNumber = number
        let callback = onResolve
        DispatchQueue.main.async {
            callback?(resolved)
        }
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
        Color.clear
            .preference(key: MainContentRenderedPreferenceKey.self, value: true)
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
                .foregroundStyle(DesignSystem.Colors.textLight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.bgMain)
    }
}

private struct StoreOpenErrorGate<Content: View>: View {
    @ObservedObject var store: AppDataStore
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            content()
            if let message = store.storeOpenError {
                StoreOpenErrorView(message: message)
                    .zIndex(1000)
            }
        }
    }
}

private struct StoreOpenErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(DesignSystem.Fonts.main(size: 40))
                .foregroundStyle(.secondary)
            Text("Could Not Open Data Store")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Text("Quit and relaunch the app. If the problem persists, restore from a backup or contact support.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.bgMain)
    }
}

private struct ModalOverlayRouter: View {
    var coordinator: ModalCoordinator

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .sheet(isPresented: catalogCourseSheetPresented) {
                catalogCourseSheetContent
            }
    }

    private var catalogCourseSheetPresented: Binding<Bool> {
        Binding(
            get: {
                guard let modal = coordinator.activeModal else { return false }
                switch modal {
                case .addGenEdCourse, .addCatalogCourseGlobal, .addCatalogCourse, .assignRequirementCourse:
                    return true
                default:
                    return false
                }
            },
            set: { isPresented in
                guard !isPresented else { return }
                guard let modal = coordinator.activeModal else { return }
                switch modal {
                case .addGenEdCourse, .addCatalogCourseGlobal, .addCatalogCourse, .assignRequirementCourse:
                    coordinator.activeModal = nil
                default:
                    break
                }
            }
        )
    }

    @ViewBuilder
    private var catalogCourseSheetContent: some View {
        if let modal = coordinator.activeModal {
            switch modal {
            case .addGenEdCourse:
                GenEdAddCourseModal(
                    targetSemesterID: nil,
                    tagAsGenEd: true
                )
                .dismissOnOutsideClickForSheet()
            case .addCatalogCourseGlobal(let tagAsGenEd):
                GenEdAddCourseModal(
                    targetSemesterID: nil,
                    tagAsGenEd: tagAsGenEd
                )
                .dismissOnOutsideClickForSheet()
            case .addCatalogCourse(let semesterID):
                GenEdAddCourseModal(
                    targetSemesterID: semesterID,
                    tagAsGenEd: false
                )
                .dismissOnOutsideClickForSheet()
            case .assignRequirementCourse(let assignment):
                GenEdAddCourseModal(
                    targetSemesterID: nil,
                    tagAsGenEd: false,
                    fulfillmentAssignment: assignment
                )
                .dismissOnOutsideClickForSheet()
            default:
                EmptyView()
                    .dismissOnOutsideClickForSheet()
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

#Preview {
    ContentView()
        .appContainerEnvironment(AppContainer.makeMainWindow())
}
