// ResumeManagerView.swift
// Feature: Career / Resumes
// Purpose: Resume library manager — table list + profile drill-down.

import SwiftUI
import AppKit
import Quartz
import CollegeCareer

struct ResumeManagerView: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.openWindow) private var openWindow
    @Binding var selectedJobID: UUID?
    var onBuildResume: (() -> Void)?
    @Binding var pendingProfileImportResumeID: UUID?

    init(
        selectedJobID: Binding<UUID?>,
        onBuildResume: (() -> Void)? = nil,
        pendingProfileImportResumeID: Binding<UUID?> = .constant(nil)
    ) {
        _selectedJobID = selectedJobID
        self.onBuildResume = onBuildResume
        _pendingProfileImportResumeID = pendingProfileImportResumeID
    }
    @State private var resumePendingDelete: VaultDocument?
    @State private var showDeleteConfirm = false

    private var collegePersistence: CollegePersistence { appContainer.persistence }
    private var notifications: AppNotificationCenter { appContainer.appNotifications }
    @State private var showingImporter = false
    @State private var openedProfileResumeID: UUID?
    @State private var quickLookURL: URL?
    @State private var autoReingestedResumeIDs: Set<UUID> = []
    @State private var showTailoringSheet = false
    @State private var tailoringSession: CareerResumeEditSession?
    @State private var showAutofillSheet = false
    @State private var autofillDiff: ProfileAutofillDiff?
    @State private var resumes: [VaultDocument] = []

    var body: some View {
        Group {
            if let profileResume = openedProfileResume {
                ResumeProfileView(
                    resume: profileResume,
                    onClose: { openedProfileResumeID = nil },
                    onReingest: { reingest(profileResume) },
                    onExport: { exportResume(profileResume) },
                    onDelete: {
                        resumePendingDelete = profileResume
                        showDeleteConfirm = true
                    },
                    onImportToProfile: { openAutofillReview(for: profileResume) },
                    onOpenJob: { jobID in
                        selectedJobID = jobID
                        appContainer.careerNavigationRouter.boardJob(id: jobID)
                    }
                )
            } else {
                ResumeLibraryTableView(
                    resumes: sortedResumes,
                    collegePersistence: collegePersistence,
                    onOpenProfile: { openedProfileResumeID = $0.id },
                    onAddResume: { showingImporter = true },
                    onBuildResume: openResumeBuilder,
                    onReingest: reingest,
                    onSetPrimary: setPrimary,
                    onToggleArchived: toggleArchived,
                    onDelete: confirmDelete,
                    onQuickLook: openQuickLook
                )
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.pdf, .plainText, .rtf],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                handleResumeImport(from: url)
            }
        }
        .onAppear {
            reloadResumes()
            handlePendingProfileImportIfNeeded()
        }
        .onChange(of: collegePersistence.careerDidChangeToken) { _, _ in reloadResumes() }
        .onChange(of: pendingProfileImportResumeID) { _, _ in
            handlePendingProfileImportIfNeeded()
        }
        .background {
            CareerQueryHost {
                reloadResumes()
            }
        }
        .task {
            _ = collegePersistence.ensureCareerResumesVaultFolder()
        }
        .quickLookPreview($quickLookURL)
        .sheet(isPresented: $showTailoringSheet) {
            if let tailoringSession {
                ResumeTailoringSheet(session: tailoringSession)
                    .interactiveDismissDisabled(tailoringSession.isGenerating)
            }
        }
        .sheet(isPresented: $showAutofillSheet) {
            if let autofillDiff {
                ResumeAutofillReviewSheet(diff: autofillDiff)
            }
        }
        .confirmationDialog(
            "Delete this resume?",
            isPresented: $showDeleteConfirm,
            presenting: resumePendingDelete
        ) { resume in
            Button("Delete", role: .destructive) {
                deleteResume(resume)
            }
        } message: { resume in
            Text("\"\(resume.customDisplayName ?? resume.fileName)\" will be removed from your vault.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.bgMain)
        .dropDestination(for: URL.self) { urls, _ in
            guard openedProfileResumeID == nil, let first = urls.first else { return false }
            return handleResumeImport(from: first)
        }
    }

    // MARK: - Data

    private var sortedResumes: [VaultDocument] {
        resumes.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
            return (lhs.lastOpenedAt ?? lhs.addedAt) > (rhs.lastOpenedAt ?? rhs.addedAt)
        }
    }

    private var openedProfileResume: VaultDocument? {
        guard let id = openedProfileResumeID else { return nil }
        return resumes.first(where: { $0.id == id })
    }

    private func reloadResumes() {
        resumes = CareerReadBridge.careerResumeDocuments()
        _ = ResumeDocumentMigration.repairLegacyResumesIfNeeded(
            resumes: resumes,
            collegePersistence: collegePersistence
        )
        repairStaleResumeIngestIfNeeded()
        if let id = openedProfileResumeID, !resumes.contains(where: { $0.id == id }) {
            openedProfileResumeID = nil
        }
    }

    private func repairStaleResumeIngestIfNeeded() {
        for resume in resumes {
            guard !autoReingestedResumeIDs.contains(resume.id) else { continue }
            guard needsStaleResumeIngestRepair(resume) else { continue }
            autoReingestedResumeIDs.insert(resume.id)
            collegePersistence.scheduleCareerResumeIngest(documentID: resume.id)
        }
    }

    private func needsStaleResumeIngestRepair(_ resume: VaultDocument) -> Bool {
        let meta = collegePersistence.careerResumeMetadata(for: resume)
        guard meta.ingestCompletedAt != nil else { return false }
        guard resume.fileSizeBytes > 50_000 else { return false }
        guard let issuesJSON = meta.parserIssuesJSON, issuesJSON.contains("sparse_text") else { return false }
        return true
    }

    // MARK: - Actions

    private func openResumeBuilder() {
        if let onBuildResume {
            onBuildResume()
        } else {
            openWindow(id: "resume-builder")
        }
    }

    private func handlePendingProfileImportIfNeeded() {
        guard let documentID = pendingProfileImportResumeID,
              let resume = resumes.first(where: { $0.id == documentID })
        else { return }
        openAutofillReview(for: resume)
        pendingProfileImportResumeID = nil
    }

    @discardableResult
    private func handleResumeImport(from url: URL) -> Bool {
        Task { @MainActor in
            do {
                if let doc = try await collegePersistence.importCareerResume(from: url) {
                    openedProfileResumeID = doc.id
                }
                reloadResumes()
            } catch {
                notifications.post(
                    kind: .error,
                    title: "Resume import failed",
                    message: error.localizedDescription
                )
            }
        }
        return true
    }

    private func reingest(_ resume: VaultDocument) {
        collegePersistence.scheduleCareerResumeIngest(documentID: resume.id)
    }

    private func setPrimary(_ resume: VaultDocument) {
        for doc in resumes where doc.isFavorite && doc.id != resume.id {
            collegePersistence.setCareerResumeFavorite(false, for: doc)
        }
        collegePersistence.setCareerResumeFavorite(true, for: resume)
    }

    private func toggleArchived(_ resume: VaultDocument) {
        var meta = collegePersistence.careerResumeMetadata(for: resume)
        meta.archived.toggle()
        try? collegePersistence.setCareerResumeMetadata(meta, for: resume)
    }

    private func confirmDelete(_ resume: VaultDocument) {
        resumePendingDelete = resume
        showDeleteConfirm = true
    }

    private func deleteResume(_ resume: VaultDocument) {
        collegePersistence.deleteVaultDocument(id: resume.id)
        if openedProfileResumeID == resume.id {
            openedProfileResumeID = nil
        }
        reloadResumes()
    }

    private func openQuickLook(_ resume: VaultDocument) {
        if let url = VaultDocumentAccess.urlForDocument(id: resume.id, collegePersistence: collegePersistence) {
            quickLookURL = nil
            DispatchQueue.main.async {
                quickLookURL = url
            }
        }
    }

    private func exportResume(_ resume: VaultDocument) {
        guard let sourceURL = VaultDocumentAccess.urlForDocument(id: resume.id, collegePersistence: collegePersistence) else {
            notifications.post(kind: .error, title: "Export failed", message: "Could not locate the resume file.")
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Resume"
        panel.nameFieldStringValue = resume.customDisplayName ?? resume.fileName
        panel.allowedContentTypes = [.pdf]
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destination)
            } catch {
                notifications.post(kind: .error, title: "Export failed", message: error.localizedDescription)
            }
        }
    }

    private func openAutofillReview(for doc: VaultDocument) {
        guard let structured = collegePersistence.careerResumeMetadata(for: doc).structuredProfile else {
            notifications.post(
                kind: .warning,
                title: "Nothing to import",
                message: "Re-analyze this resume so structured fields are available."
            )
            return
        }
        guard let profile = collegePersistence.ensurePrimaryProfile() else { return }
        let diff = CareerResumeProfileAutofillService.diff(
            structuredProfile: structured,
            existingProfile: profile,
            existingAcademicProfile: collegePersistence.primaryAcademicProfile
        )
        if diff.isEmpty {
            notifications.post(
                kind: .info,
                title: "Profile already filled",
                message: "Your profile already contains the resume fields we could import."
            )
            return
        }
        autofillDiff = diff
        showAutofillSheet = true
    }
}

// MARK: - Quick Look bridge

private struct LegacyQuickLookPreviewBridge: NSViewRepresentable {
    @Binding var url: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator(url: $url)
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.presentIfNeeded(with: url)
    }

    @MainActor
    final class Coordinator: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
        @Binding private var url: URL?

        init(url: Binding<URL?>) {
            self._url = url
        }

        func presentIfNeeded(with candidate: URL?) {
            guard let panel = QLPreviewPanel.shared() else { return }
            if let candidate {
                url = candidate
                panel.dataSource = self
                panel.delegate = self
                panel.reloadData()
                panel.makeKeyAndOrderFront(nil)
            } else if panel.isVisible {
                panel.orderOut(nil)
            }
        }

        func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
            url == nil ? 0 : 1
        }

        func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
            (url ?? URL(fileURLWithPath: "/")) as NSURL
        }

        func previewPanelWillClose(_ panel: QLPreviewPanel!) {
            url = nil
        }
    }
}

private extension View {
    func quickLookPreview(_ url: Binding<URL?>) -> some View {
        background(LegacyQuickLookPreviewBridge(url: url))
    }
}
