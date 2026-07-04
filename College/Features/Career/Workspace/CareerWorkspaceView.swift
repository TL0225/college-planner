// CareerWorkspaceView.swift
// Feature: Career / Workspace
// Purpose: Career workspace shell and subview routing.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import AppKit
import CollegeCareer

struct CareerWorkspaceView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.openWindow) private var openWindow
    private var collegePersistence: CollegePersistence { appContainer.persistence }
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("ui.reduceMotion") private var appReduceMotion = false

    private var persistence: CollegePersistence { appContainer.persistence }
    private var careerScene: CareerSceneState { appContainer.careerScene }
    private var careerRouter: CareerNavigationRouter { appContainer.careerNavigationRouter }
    private var toolbarDispatcher: ToolbarDispatcher { appContainer.toolbarDispatcher }

    @State private var showAddSheet = false
    @State private var toolbarHandlerToken: ToolbarHandlerToken?
    @State private var editingJobID: UUID?
    @State private var selectedJobID: UUID?
    @State private var showingResumeBuilder = false
    @State private var pendingProfileImportResumeID: UUID?
    @State private var showProfileImportPrompt = false
    @AppStorage(CareerBoardLayout.storageKey) private var boardLayoutRaw: String = CareerBoardLayout.kanban.rawValue
    @AppStorage(CareerSubView.selectedViewStorageKey) private var selectedViewRaw: String = CareerSubView.board.rawValue

    private var motionReduced: Bool { reduceMotion || appReduceMotion }

    private var boardLayout: CareerBoardLayout {
        CareerBoardLayout(rawValue: boardLayoutRaw) ?? .kanban
    }

    private var activeSubview: CareerSubView {
        careerScene.selectedView
    }

    private func setActiveSubview(_ view: CareerSubView) {
        careerScene.select(view)
    }

    var body: some View {
        careerSubviewContent
        .background(DesignSystem.Colors.bgMain)
        .shellDynamicTypeReadable()
        .accessibilityIdentifier("career.workspace.root")
        .sheet(isPresented: $showAddSheet, onDismiss: { editingJobID = nil }) {
            Group {
                if let editingJobID {
                    CareerApplicationFormSheet(existingApplicationID: editingJobID)
                        } else {
                    AddRoleSheet()
                        }
            }
        }
        .onAppear {
            careerScene.select(CareerSubView(rawValue: selectedViewRaw) ?? .board)
            registerCareerWindowToolbar()
            registerCareerNavigationHandlers()
            openResumeBuilderForUITestIfNeeded()
        }
        .onChange(of: collegePersistence.careerDidChangeToken) { _, _ in
            openResumeBuilderForUITestIfNeeded()
        }
        .onChange(of: careerScene.selectedView) { _, newValue in
            selectedViewRaw = newValue.rawValue
            if newValue == .openings {
                JobBoardSyncCoordinator.shared.markOpeningsViewed()
            }
            if newValue != .resumes {
                showingResumeBuilder = false
            }
        }
        .onChange(of: boardLayoutRaw) { _, _ in
            careerScene.boardLayout = boardLayout
        }
        .onDisappear {
            careerScene.clearHandlers()
            careerRouter.clearHandlers()
            toolbarHandlerToken?.invalidate()
            toolbarHandlerToken = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .careerResumeReadyForProfileImport)) { notification in
            guard let documentID = notification.object as? UUID else { return }
            pendingProfileImportResumeID = documentID
            showProfileImportPrompt = true
        }
        .confirmationDialog(
            "Resume imported",
            isPresented: $showProfileImportPrompt,
            titleVisibility: .visible
        ) {
            Button("Open Builder") {
                guard let documentID = pendingProfileImportResumeID else { return }
                ResumeNavigationPort.openResumeBuilder(openWindow: openWindow, documentID: documentID)
                pendingProfileImportResumeID = nil
            }
            Button("Review for Profile") {
                setActiveSubview(.resumes)
            }
            Button("Dismiss", role: .cancel) {
                pendingProfileImportResumeID = nil
            }
        } message: {
            Text("Review in Builder or import fields into your Profile?")
        }
        .onReceive(NotificationCenter.default.publisher(for: .collegeImportSharedResume)) { notification in
            setActiveSubview(.resumes)
            Task { @MainActor in
                await importSharedResume(requestIDString: notification.object as? String)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .collegeOpenResumeBuilder)) { notification in
            setActiveSubview(.resumes)
            if let documentID = notification.object as? UUID {
                ResumeNavigationPort.openResumeBuilder(openWindow: openWindow, documentID: documentID)
            } else {
                ResumeNavigationPort.openResumeBuilder(openWindow: openWindow)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .collegeCareerToggleInspector)) { _ in
            if selectedJobID != nil {
                selectedJobID = nil
            } else {
                NotificationCenter.default.post(name: .collegeCareerOpenInspectorSelection, object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .careerSelectSubview)) { notification in
            guard let raw = notification.userInfo?["rawValue"] as? String,
                  let view = CareerSubView(rawValue: raw) else { return }
            setActiveSubview(view)
        }
        .onReceive(NotificationCenter.default.publisher(for: .collegeCareerAddApplication)) { _ in
            editingJobID = nil
            showAddSheet = true
        }
        .environment(careerRouter)
    }

    @ViewBuilder
    private var careerSubviewContent: some View {
        Group {
            switch activeSubview {
            case .board:
                ApplicationTrackerView(
                    selectedJobID: $selectedJobID,
                    boardLayout: boardLayout
                )
            case .openings:
                JobOpeningsView(onNavigateToApplicationTracker: { setActiveSubview(.board) })
                    case .stats:
                CareerStatsView()
                    case .resumes:
                if showingResumeBuilder {
                    ResumeBuilderRoot(
                        presentation: .inline,
                        onExit: { showingResumeBuilder = false },
                        onPopOut: {
                            showingResumeBuilder = false
                            openWindow(id: "resume-builder")
                        }
                    )
                } else {
                    ResumeManagerView(
                        selectedJobID: $selectedJobID,
                        onBuildResume: { showingResumeBuilder = true },
                        pendingProfileImportResumeID: $pendingProfileImportResumeID
                    )
                }
            case .applyProfile:
                CareerApplicationProfileView()
            case .stories:
                InterviewPrepView()
            case .networking:
                NetworkingTrackerView(selectedJobID: $selectedJobID)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity.combined(with: .scale(scale: motionReduced ? 1 : 0.98)))
    }

    private func registerCareerWindowToolbar() {
        careerScene.boardLayout = boardLayout
        careerScene.onBoardLayoutChange = { layout in
            boardLayoutRaw = layout.rawValue
        }
        toolbarHandlerToken?.invalidate()
        toolbarHandlerToken = toolbarDispatcher.register(owner: .career) { [self] action in
            guard case .career(let careerAction) = action else { return }
            switch careerAction {
            case .addApplication:
                editingJobID = nil
                showAddSheet = true
            case .copyBoardMarkdown:
                let apps = (try? collegePersistence.careerRepository.fetchApplications(limit: 500)) ?? []
                let md = CareerBoardMarkdownExport.table(from: apps)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(md, forType: .string)
            }
        }
    }

    private func registerCareerNavigationHandlers() {
        careerRouter.openAddApplication = {
            editingJobID = nil
            showAddSheet = true
        }
        careerRouter.openEditApplication = { jobID in
            editingJobID = jobID
            showAddSheet = true
        }
        careerRouter.openBoardJob = { jobID in
            setActiveSubview(.board)
            selectedJobID = jobID
        }
        careerRouter.openJobOpenings = {
            setActiveSubview(.openings)
        }
    }

    private func openResumeBuilderForUITestIfNeeded() {
        guard UITestLaunchFlags.autoOpenResumeBuilder, !showingResumeBuilder else { return }
        let resumes = CareerReadBridge.careerResumeDocuments(collegePersistence: collegePersistence)
        guard !resumes.isEmpty else { return }
        setActiveSubview(.resumes)
        showingResumeBuilder = true
    }

    private func importSharedResume(requestIDString: String?) async {
        guard let requestIDString,
              let requestID = UUID(uuidString: requestIDString),
              let stagedURL = CareerIngestCoordinator.shared.consumeSharedResumeImport(requestId: requestID)
        else {
            appContainer.appNotifications.post(
                kind: .error,
                title: "Resume import expired",
                message: "Share the PDF again from the source app."
            )
            return
        }
        defer { try? CareerIngestCoordinator.shared.deleteSharedResumeImport(requestId: requestID) }
        do {
            if let document = try await collegePersistence.importCareerResume(from: stagedURL) {
                pendingProfileImportResumeID = document.id
                showProfileImportPrompt = true
            }
        } catch {
            appContainer.appNotifications.post(
                kind: .error,
                title: "Resume import failed",
                message: error.localizedDescription
            )
        }
    }
}
