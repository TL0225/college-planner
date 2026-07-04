// CareerApplyWindowRoot.swift
// Feature: Career / Apply
// Purpose: Dedicated apply window — web view + fill report side panel.

import SwiftUI
import CollegeCareer
import AppKit

struct CareerApplyWindowRoot: View {
    @Environment(AppContainer.self) private var appContainer
    @Environment(\.dismissWindow) private var dismissWindow

    let sessionID: CareerApplySessionID

    @State private var coordinator: CareerApplyCoordinator?
    @State private var showCompletion = false
    @State private var appliedAt = Date()
    @State private var showReview = false
    @State private var pendingPayload: CareerApplicationAutofillPayload?
    @State private var showSavePasswordSheet = false
    @State private var pendingCredentialHost = ""
    @State private var pendingCredentialUsername = ""
    @State private var pendingCredentialPassword = ""
    @State private var availableResumes: [VaultDocument] = []

    private var store: CareerApplySessionStore { .shared }

    var body: some View {
        Group {
            if let session = store.session(for: sessionID.id) {
                applyContent(session: session)
            } else {
                ContentUnavailableView("Apply session ended", systemImage: "xmark.circle")
            }
        }
        .onAppear { bootstrapSession() }
        .task { loadAvailableResumes() }
        .onDisappear {
            // Traffic-light close skips `closeWindow()`; always drop temp resume PDFs.
            store.close(id: sessionID.id)
            coordinator?.tearDown()
            coordinator = nil
        }
        .onChange(of: coordinator?.offerSavePassword) { _, offer in
            guard let offer else { return }
            pendingCredentialHost = offer.host
            pendingCredentialUsername = offer.username
            pendingCredentialPassword = ""
            showSavePasswordSheet = true
        }
        .sheet(isPresented: $showSavePasswordSheet) {
            CareerApplySavePasswordSheet(
                host: pendingCredentialHost,
                username: pendingCredentialUsername,
                password: $pendingCredentialPassword,
                onSave: {
                    WebPortalKeychainService.shared.save(
                        username: pendingCredentialUsername,
                        password: pendingCredentialPassword,
                        host: pendingCredentialHost
                    )
                    showSavePasswordSheet = false
                    coordinator?.dismissSavePasswordOffer()
                },
                onSkip: {
                    showSavePasswordSheet = false
                    coordinator?.dismissSavePasswordOffer()
                }
            )
        }
    }

    @ViewBuilder
    private func applyContent(session: CareerApplySession) -> some View {
        HSplitView {
            Group {
                if let coordinator {
                    CareerApplyWebHostView(webView: coordinator.view)
                } else {
                    ProgressView("Loading apply page…")
                }
            }
            .frame(minWidth: 520)

            applySidePanel(session: session)
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
        }
        .navigationTitle(session.jobTitle)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    coordinator?.presentFindNavigator()
                } label: {
                    Label("Find", systemImage: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: .command)
                .help("Find in page")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Mark application complete") { showCompletion = true }
                    .disabled(session.status == .completed)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { closeWindow() }
            }
        }
        .sheet(isPresented: $showReview) {
            if let pendingPayload {
                CareerApplyFieldReviewSheet(
                    payload: pendingPayload,
                    onApprove: { approved in
                        var updated = session
                        updated.payload = approved
                        updated.status = .filling
                        store.update(updated)
                        coordinator?.runAutofill()
                        showReview = false
                    },
                    onCancel: { showReview = false }
                )
            }
        }
        .sheet(isPresented: $showCompletion) {
            CareerApplyCompletionSheet(
                companyName: session.companyName,
                resumeFileName: session.resumeFileName,
                appliedAt: $appliedAt,
                onConfirm: { confirmCompletion(session: session) },
                onCancel: { showCompletion = false }
            )
        }
    }

    @ViewBuilder
    private func applySidePanel(session: CareerApplySession) -> some View {
        List {
            Section("Session") {
                LabeledContent("Company", value: session.companyName)
                LabeledContent("Platform", value: session.platform.displayName)
                LabeledContent("Tier", value: CareerApplyTierRegistry.tier(for: session.platform).displayName)
                if let reason = session.manualOnlyReason ?? coordinator?.manualOnlyBanner {
                    Text(reason).foregroundStyle(.orange).font(.caption)
                }
            }
            if let report = coordinator?.verificationReport, !report.fields.isEmpty {
                Section("Fill report") {
                    ForEach(report.fields) { field in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(field.atsLabel ?? field.payloadKey).font(.caption.weight(.semibold))
                            Text("Intended: \(field.intended)").font(.caption2)
                            if let filled = field.filled {
                                Text("Filled: \(filled)").font(.caption2)
                            }
                            Label(field.verified ? "Verified" : field.status.rawValue, systemImage: field.verified ? "checkmark.circle.fill" : "exclamationmark.triangle")
                                .font(.caption2)
                                .foregroundStyle(field.verified ? .green : .orange)
                        }
                    }
                }
            }
            Section("Resume") {
                LabeledContent("Attached", value: session.resumeFileName)
                if availableResumes.count > 1 {
                    Menu("Change resume") {
                        ForEach(availableResumes, id: \.id) { resume in
                            Button(resume.customDisplayName ?? resume.fileName) {
                                switchResume(to: resume.id, session: session)
                            }
                            .disabled(resume.id == session.resumeDocumentID)
                        }
                    }
                }
            }
            Section {
                Button("Run autofill") {
                    if session.payload != nil {
                        coordinator?.runAutofill()
                    } else {
                        prepareReview(session: session)
                    }
                }
                .disabled(coordinator == nil || session.status == .manualOnly)
            }
        }
        .listStyle(.sidebar)
    }

    private func bootstrapSession() {
        guard let session = store.session(for: sessionID.id) else { return }
        let coord = CareerApplyCoordinator(session: session)
        coordinator = coord
        coord.loadApplyURL()
        if session.payload != nil {
            showReview = true
            pendingPayload = session.payload
        }
    }

    private func prepareReview(session: CareerApplySession) {
        do {
            let rebuilt = try store.rebuildPayload(
                for: session.id,
                collegePersistence: appContainer.persistence
            )
            pendingPayload = rebuilt?.payload
            showReview = true
        } catch {
            coordinator?.manualOnlyBanner = error.localizedDescription
        }
    }

    private func loadAvailableResumes() {
        availableResumes = CareerReadBridge.careerResumeDocuments(
            collegePersistence: appContainer.persistence
        )
        .filter { !appContainer.persistence.careerResumeMetadata(for: $0).archived }
    }

    private func switchResume(to resumeDocumentID: UUID, session: CareerApplySession) {
        do {
            guard let rebuilt = try store.rebuildPayload(
                for: session.id,
                resumeDocumentID: resumeDocumentID,
                collegePersistence: appContainer.persistence
            ) else { return }
            coordinator?.replaceSession(rebuilt)
            pendingPayload = rebuilt.payload
            appContainer.appNotifications.post(
                kind: .info,
                title: "Resume switched",
                message: "Autofill will use \(rebuilt.resumeFileName)."
            )
        } catch {
            coordinator?.manualOnlyBanner = error.localizedDescription
        }
    }

    private func confirmCompletion(session: CareerApplySession) {
        guard let jobID = session.jobApplicationID else {
            showCompletion = false
            closeWindow()
            return
        }
        let repo = CareerRepository(context: appContainer.persistence.profileContext)
        do {
            try repo.recordApplyCompletion(
                applicationID: jobID,
                session: session,
                appliedAt: appliedAt,
                fillReport: coordinator?.verificationReport ?? .empty
            )
            var done = session
            done.status = .completed
            store.update(done)
            appContainer.careerScene.select(.board)
        } catch {
            coordinator?.manualOnlyBanner = error.localizedDescription
        }
        showCompletion = false
        closeWindow()
    }

    private func closeWindow() {
        store.close(id: sessionID.id)
        coordinator?.tearDown()
        dismissWindow(id: "career-apply", value: sessionID)
    }
}
