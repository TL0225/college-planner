// ResumeBuilderRoot.swift
// Feature: Resume
// Purpose: Guided resume builder window root view.

import Combine
import SwiftUI

enum ResumeBuilderPresentation {
    /// Detached `Window` scene.
    case window
    /// Embedded as the Career section's detail content.
    case inline
}

struct ResumeBuilderRoot: View {
    @Environment(AppContainer.self) private var appContainer
    @State private var viewModel: ResumeBuilderViewModel?
    @State private var schoolName: String?

    /// When set, hydrates the builder from the vault resume's `documentJSON` sidecar.
    var restoringDocumentID: UUID?
    var presentation: ResumeBuilderPresentation = .window
    /// Called when the inline builder should return to the resume library.
    var onExit: (() -> Void)?
    /// Called when the user wants to detach the inline builder into a window.
    var onPopOut: (() -> Void)?

    private var collegePersistence: CollegePersistence { appContainer.persistence }

    var body: some View {
        rootContent
            .frame(
                minWidth: presentation == .window ? 1040 : nil,
                minHeight: presentation == .window ? 700 : nil
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ResumeBuilderWindowChromeAttacher(presentation: presentation))
            .task(id: restoringDocumentID) {
                await bootstrap()
            }
    }

    @ViewBuilder
    private var rootContent: some View {
        if presentation == .window {
            loadedContent
                .navigationTitle("Resume Builder")
                .navigationSubtitle(windowSubtitle)
        } else {
            loadedContent
        }
    }

    @ViewBuilder
    private var loadedContent: some View {
        if let viewModel {
            ResumeBuilderContentView(
                viewModel: viewModel,
                collegePersistence: collegePersistence,
                notifications: appContainer.appNotifications,
                schoolName: schoolName,
                presentation: presentation,
                onExit: onExit,
                onPopOut: onPopOut
            )
        } else {
            ProgressView("Loading profile…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var windowSubtitle: String {
        let edited = viewModel?.hasUnsavedChanges == true
        switch (schoolName, edited) {
        case (.some(let name), true): return "\(name) — Edited"
        case (.some(let name), false): return name
        case (.none, true): return "Edited"
        case (.none, false): return ""
        }
    }

    @MainActor
    private func bootstrap() async {
        schoolName = ProfileReadBridge.shellSnapshot(collegePersistence: collegePersistence).collegeName

        if let documentID = restoringDocumentID {
            if viewModel?.linkedVaultDocumentID == documentID { return }
            if let document = ResumeDocumentRestore.load(
                documentID: documentID,
                collegePersistence: collegePersistence
            ) {
                viewModel = ResumeBuilderViewModel(
                    restoredDocument: document,
                    collegePersistence: collegePersistence,
                    linkedVaultDocumentID: documentID
                )
                ProductAnalytics.track(.resumeBuilderOpened, properties: ["restored": "true"])
                return
            }
        }

        guard restoringDocumentID == nil else { return }
        guard viewModel == nil else { return }
        if let snapshot = try? ResumeSnapshotBuilder.build(collegePersistence: collegePersistence) {
            viewModel = ResumeBuilderViewModel(snapshot: snapshot, collegePersistence: collegePersistence)
            ProductAnalytics.track(.resumeBuilderOpened)
        }
    }
}

private struct ResumeBuilderContentView: View {
    @Bindable var viewModel: ResumeBuilderViewModel
    let collegePersistence: CollegePersistence
    let notifications: AppNotificationCenter
    let schoolName: String?
    var presentation: ResumeBuilderPresentation = .window
    var onExit: (() -> Void)?
    var onPopOut: (() -> Void)?

    @State private var showUnsavedExitPrompt = false
    @State private var showAdvancedConfirm = false
    @State private var showExportPreflight = false
    @State private var pendingExportAction: ResumeBuilderExportAction = .exportPDF

    var body: some View {
        VStack(spacing: 0) {
            if presentation == .inline {
                inlineBackBar
            }

            builderHeader

            if viewModel.profileIsStale {
                staleProfileBanner
            }

            ResumeHomeRibbon(viewModel: viewModel, collegePersistence: collegePersistence)

            HSplitView {
                ResumeBuilderCategorySidebar(viewModel: viewModel)
                    .frame(minWidth: 200, idealWidth: 240, maxWidth: 280)

                centerPane
                    .frame(minWidth: 300, idealWidth: 420, maxWidth: .infinity)

                previewPane
                    .frame(minWidth: 320, idealWidth: 460, maxWidth: .infinity)
            }

            ResumeBuilderChecklistFooter(viewModel: viewModel)
        }
        .documentEdited(presentation == .window && viewModel.hasUnsavedChanges)
        .accessibilityIdentifier("resume.builder.root")
        .toolbar {
            if presentation == .window {
                ToolbarItem(placement: .primaryAction) {
                    Button("Save to Library") {
                        requestSaveToLibrary()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.previewData == nil)
                    .accessibilityIdentifier("resume.builder.saveToLibrary")
                }
                ToolbarItem(placement: .automatic) {
                    overflowMenu
                }
            }
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            viewModel.checkProfileStaleness()
        }
        .confirmationDialog(
            "You have unsaved changes",
            isPresented: $showUnsavedExitPrompt,
            titleVisibility: .visible
        ) {
            Button("Save & Close") {
                performSaveToLibrary()
                onExit?()
            }
            Button("Discard Changes", role: .destructive) {
                onExit?()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save this resume to your library before leaving the builder?")
        }
        .confirmationDialog(
            "Open advanced source?",
            isPresented: $showAdvancedConfirm,
            titleVisibility: .visible
        ) {
            Button("Open Advanced") {
                viewModel.setShowAdvancedSource(true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This is for advanced editing. Most people use the form fields.")
        }
        .sheet(isPresented: $showExportPreflight) {
            ResumeBuilderExportPreflightSheet(
                profile: exportReviewProfile,
                parserHealthPercent: linkedParserHealthPercent,
                requiresManualTypstConfirm: viewModel.requiresManualResetConfirmation(),
                action: pendingExportAction,
                onConfirm: {
                    showExportPreflight = false
                    switch pendingExportAction {
                    case .exportPDF: performExportPDF()
                    case .saveToLibrary: performSaveToLibrary()
                    }
                },
                onCancel: { showExportPreflight = false }
            )
        }
    }

    private var exportReviewProfile: CareerResumeStructuredProfile {
        let snapshot = ResumeDocumentCompiler.mergedSnapshot(from: viewModel.document)
        return ResumeCanonicalProfile.from(snapshot: snapshot).toStructuredProfile()
    }

    private var linkedParserHealthPercent: Int? {
        guard let id = viewModel.linkedVaultDocumentID,
              let doc = try? collegePersistence.vaultRepository.fetchDocument(id: id)
        else { return nil }
        return collegePersistence.careerResumeMetadata(for: doc).parserHealthPercent
    }

    private func requestExportPDF() {
        pendingExportAction = .exportPDF
        showExportPreflight = true
    }

    private func requestSaveToLibrary() {
        pendingExportAction = .saveToLibrary
        showExportPreflight = true
    }

    @ViewBuilder
    private var centerPane: some View {
        if viewModel.showAdvancedSource {
            ResumeTypstSourceEditor(viewModel: viewModel)
        } else {
            ResumeBuilderFieldEditor(viewModel: viewModel)
        }
    }

    private var builderHeader: some View {
        HStack(spacing: 12) {
            TextField("Resume title", text: titleBinding)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
                .accessibilityIdentifier("resume.builder.title")
                .accessibilityLabel("Resume title")

            if viewModel.hasUnsavedChanges {
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 7, height: 7)
                    .help("Unsaved changes")
                    .accessibilityLabel("Unsaved changes")
            }

            Spacer()

            Toggle("Advanced source", isOn: advancedSourceBinding)
                .toggleStyle(.switch)
                .controlSize(.small)
                .help("Show Typst source editor")
                .accessibilityIdentifier("resume.builder.advancedSource")
                .accessibilityLabel("Advanced source")
                .accessibilityHint("Shows Typst source editor for advanced editing")

            if presentation == .inline {
                inlineOverflowMenu
                capsuleButton("Save to Library", filled: true, isEnabled: viewModel.previewData != nil) {
                    requestSaveToLibrary()
                }
                .accessibilityIdentifier("resume.builder.saveToLibrary")
                capsuleButton("Pop out", systemImage: "macwindow.on.rectangle", filled: false, isEnabled: true) {
                    onPopOut?()
                }
            } else {
                Button("Export PDF…") {
                    requestExportPDF()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.previewData == nil)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, presentation == .inline ? 0 : 16)
        .padding(.bottom, 12)
        .background(DesignSystem.Colors.bgMain)
    }

    private var inlineBackBar: some View {
        HStack(spacing: 12) {
            Button {
                handleExit()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Resumes")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.primary)
            }
            .buttonStyle(.plain)

            Divider().frame(height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text("Resume Builder")
                    .font(.headline)
                if let schoolName {
                    Text(schoolName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 8)
        .background(DesignSystem.Colors.bgMain)
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PREVIEW")
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            ResumeBuilderPreviewView(
                pdfData: viewModel.previewData,
                isCompiling: viewModel.compileState == .compiling,
                usingFallback: viewModel.usingFallback,
                emptySectionWarnings: viewModel.emptySectionWarnings,
                compileError: compileErrorMessage
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DesignSystem.Colors.bgMain)
    }

    private var overflowMenu: some View {
        Menu {
            Button("Reset Order", systemImage: "arrow.uturn.backward") {
                viewModel.resetOrder()
            }
            Button("Export PDF…", systemImage: "square.and.arrow.up") {
                exportPDF()
            }
            .disabled(viewModel.previewData == nil)
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .menuIndicator(.hidden)
    }

    private var inlineOverflowMenu: some View {
        Menu {
            Button("Reset Order", systemImage: "arrow.uturn.backward") {
                viewModel.resetOrder()
            }
            Button("Export PDF…", systemImage: "square.and.arrow.up") {
                exportPDF()
            }
            .disabled(viewModel.previewData == nil)
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DesignSystem.Colors.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(DesignSystem.Colors.surface, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(DesignSystem.Colors.primary.opacity(0.35), lineWidth: 1)
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var staleProfileBanner: some View {
        HStack(spacing: 12) {
            Label("Profile updated — Refresh", systemImage: "arrow.clockwise")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button("Refresh") {
                viewModel.refreshSnapshot()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
    }

    private var titleBinding: Binding<String> {
        Binding(
            get: { viewModel.document.title },
            set: { viewModel.updateTitle($0) }
        )
    }

    private var advancedSourceBinding: Binding<Bool> {
        Binding(
            get: { viewModel.showAdvancedSource },
            set: { newValue in
                if newValue, !viewModel.showAdvancedSource {
                    showAdvancedConfirm = true
                } else {
                    viewModel.setShowAdvancedSource(newValue)
                }
            }
        )
    }

    private var compileErrorMessage: String? {
        if case .failed(let message) = viewModel.compileState {
            return message
        }
        return nil
    }

    private func handleExit() {
        if viewModel.hasUnsavedChanges {
            showUnsavedExitPrompt = true
        } else {
            onExit?()
        }
    }

    private func performSaveToLibrary() {
        guard let pdfData = viewModel.currentPDFData() else { return }
        Task {
            do {
                let metadata = viewModel.buildMetadata()
                let name = viewModel.defaultExportFilename()
                if let saved = try await ResumeBuilderExportService.saveToLibrary(
                    pdfData: pdfData,
                    metadata: metadata,
                    displayName: name,
                    document: viewModel.document,
                    collegePersistence: collegePersistence,
                    existingVaultDocumentID: viewModel.linkedVaultDocumentID
                ) {
                    viewModel.linkVaultDocument(saved.id)
                    ProductAnalytics.track(.resumeDraftSaved)
                    notifications.post(
                        kind: .success,
                        title: "Resume saved",
                        message: "Your resume was added to the library."
                    )
                }
            } catch {
                notifications.post(
                    kind: .error,
                    title: "Save failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func performExportPDF() {
        guard let pdfData = viewModel.currentPDFData() else { return }
        let saved = ResumeBuilderExportService.exportToUserChosenDestination(
            pdfData: pdfData,
            defaultFileName: viewModel.defaultExportFilename()
        )
        if saved {
            ProductAnalytics.track(.resumeExported)
            notifications.post(
                kind: .success,
                title: "Resume exported",
                message: "PDF saved to the chosen location."
            )
        }
    }

    private func saveToLibrary() {
        requestSaveToLibrary()
    }

    private func exportPDF() {
        requestExportPDF()
    }

    @ViewBuilder
    private func capsuleButton(
        _ title: String,
        systemImage: String? = nil,
        filled: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(filled ? Color.white : DesignSystem.Colors.primary)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(
            filled ? DesignSystem.Colors.primary : DesignSystem.Colors.surface,
            in: Capsule(style: .continuous)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    filled ? Color.clear : DesignSystem.Colors.primary.opacity(0.35),
                    lineWidth: 1
                )
        )
        .opacity(isEnabled ? 1 : 0.5)
        .disabled(!isEnabled)
    }
}

private extension View {
    func documentEdited(_ edited: Bool) -> some View {
        background(DocumentEditedReflector(isEdited: edited))
    }
}

private struct DocumentEditedReflector: NSViewRepresentable {
    let isEdited: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.isDocumentEdited = isEdited }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { nsView.window?.isDocumentEdited = isEdited }
    }
}
