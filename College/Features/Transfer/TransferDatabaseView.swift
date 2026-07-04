// TransferDatabaseView.swift
// Feature: Transfer
// Purpose: Transfer Database — page UI: pick a source school, refresh sources, review impact.
// Owner: registers `.transfer` toolbar handler; reads AppContainer scene + coordinator.

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct TransferDatabaseView: View {
    @Environment(AppContainer.self) private var appContainer
    @Binding var activePage: AppPage

    private var scene: TransferSceneState { appContainer.transferScene }
    private var coordinator: TransferCoordinator { appContainer.transferCoordinator }
    private var toolbarDispatcher: ToolbarDispatcher { appContainer.toolbarDispatcher }

    @State private var toolbarHandlerToken: ToolbarHandlerToken?
    @State private var showCommunityImporter = false
    @State private var showManualEntrySheet = false
    @State private var manualEntryFeedback: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                sourcePicker
                statusBar
                if let manualEntryFeedback {
                    Text(manualEntryFeedback)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if scene.results.isEmpty {
                    emptyState
                } else {
                    resultsSection
                    impactSection
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DesignSystem.Colors.bgMain)
        .onAppear {
            coordinator.bootstrap()
            registerToolbar()
        }
        .onDisappear {
            toolbarHandlerToken?.invalidate()
            toolbarHandlerToken = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .transferImportCommunityJSON)) { _ in
            showCommunityImporter = true
        }
        .fileImporter(
            isPresented: $showCommunityImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task {
                    let count = await coordinator.importCommunity(fileURL: url)
                    manualEntryFeedback = count > 0
                        ? "Imported \(count) community equivalencies."
                        : "Community import finished with no new rows."
                }
            }
        }
        .sheet(isPresented: $showManualEntrySheet) {
            TransferManualEntrySheet(
                sourceSchoolName: scene.sourceSchoolName,
                defaultTargetSchoolName: scene.targetSchool?.name ?? ""
            ) { draft, proofPDFURL in
                switch await coordinator.saveManualEntry(draft, proofPDFURL: proofPDFURL) {
                case .saved(let proofNote):
                    var message = "Saved manual equivalency \(draft.sourceCourseCode) → \(draft.targetCourseCode)."
                    if let proofNote {
                        message += " \(proofNote)"
                    }
                    manualEntryFeedback = message
                    return nil
                case .validationFailed(let message):
                    return message
                case .missingTargetSchool:
                    return TransferError.missingTargetSchool.localizedDescription
                }
            }
        }
    }

    // MARK: - Sections

    private var sourcePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transferring from")
                .font(.headline)
            HStack(spacing: 12) {
                TextField("Source school name", text: Binding(
                    get: { scene.sourceSchoolName },
                    set: { scene.sourceSchoolName = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360)

                Picker("Mode", selection: Binding(
                    get: { scene.mode },
                    set: { scene.mode = $0 }
                )) {
                    Text("Sample").tag(TransferSourceMode.fixture)
                    Text("Live").tag(TransferSourceMode.live)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                Button {
                    Task { await coordinator.refreshOfficial() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(scene.isRefreshing || scene.sourceSchoolName.trimmingCharacters(in: .whitespaces).isEmpty)

                Button("Import JSON") { showCommunityImporter = true }

                Button {
                    showManualEntrySheet = true
                } label: {
                    Label("Add Manual", systemImage: "square.and.pencil")
                }
            }

            if let target = scene.targetSchool {
                Text("Transferring into \(target.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Set your target university in Profile to score degree impact.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            if scene.isRefreshing {
                ProgressView().controlSize(.small)
            }
            Text(statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            if !scene.routesAttempted.isEmpty {
                Text("Sources: " + scene.routesAttempted.map { $0.rawValue }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.left.arrow.right.circle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No transfer equivalencies yet")
                .font(.headline)
            Text("Enter a source school, refresh official sources, import a JSON dataset, or add a manual mapping.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showManualEntrySheet = true
            } label: {
                Label("Add Manual Equivalency", systemImage: "square.and.pencil")
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Equivalencies (\(scene.results.count))")
                    .font(.headline)
                Spacer()
                if coordinator.batchSubmissionURL() != nil {
                    Button {
                        openCommunityURL(coordinator.batchSubmissionURL())
                    } label: {
                        Label("Share All", systemImage: "square.and.arrow.up")
                    }
                }
            }
            ForEach(scene.results) { result in
                TransferResultRow(
                    result: result,
                    onShareToCommunity: {
                        openCommunityURL(coordinator.submissionURL(for: result))
                    },
                    onDeleteManual: result.isManualEntry ? {
                        coordinator.deleteManualEntry(dedupeKey: result.dedupeKey)
                        manualEntryFeedback = "Removed manual entry for \(result.sourceCourseCode)."
                    } : nil
                )
            }
        }
    }

    private var impactSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Degree Impact")
                    .font(.headline)
                Spacer()
                Text("\(scene.projectedTransferCredits) projected credits")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignSystem.Colors.primary)
            }
            if scene.impactRows.isEmpty {
                Text("No matching degree requirements found for your active program.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(scene.impactRows) { row in
                    TransferImpactRowView(row: row)
                }
            }
        }
    }

    private var statusText: String {
        switch scene.refreshStatus {
        case .idle: return scene.results.isEmpty ? "Ready" : "\(scene.results.count) equivalencies loaded"
        case .running: return "Refreshing sources…"
        case .success: return "Refresh complete"
        case .partial: return "Refresh complete (some sources failed)"
        case .failed: return scene.lastErrorMessage ?? "Refresh failed"
        case .throttled: return "Source paced requests — try again shortly"
        }
    }

    private func registerToolbar() {
        toolbarHandlerToken?.invalidate()
        toolbarHandlerToken = toolbarDispatcher.register(owner: .transfer) { action in
            guard case .transfer(let transferAction) = action else { return }
            switch transferAction {
            case .refreshOfficial:
                Task { await coordinator.refreshOfficial() }
            case .importCommunity:
                showCommunityImporter = true
            case .addManualEntry:
                showManualEntrySheet = true
            case .shareToCommunity:
                openCommunityURL(coordinator.batchSubmissionURL())
            case .toggleMode:
                scene.mode = scene.mode == .fixture ? .live : .fixture
            }
        }
    }

    private func openCommunityURL(_ url: URL?) {
        guard let url else {
            manualEntryFeedback = "Could not build a community submission link."
            return
        }
        NSWorkspace.shared.open(url)
    }
}

private struct TransferResultRow: View {
    let result: TransferCourseResult
    let onShareToCommunity: () -> Void
    let onDeleteManual: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.sourceCourseCode)
                    .font(.body.weight(.semibold))
                if let title = result.sourceCourseTitle {
                    Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(width: 160, alignment: .leading)

            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.targetCourseCode)
                    .font(.body.weight(.semibold))
                if let title = result.targetCourseTitle {
                    Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                Text(result.equivalencyKind.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(result.primarySourceLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            confidenceBadge

            Menu {
                Button {
                    onShareToCommunity()
                } label: {
                    Label("Share to Community", systemImage: "square.and.arrow.up")
                }
                if let onDeleteManual {
                    Divider()
                    Button(role: .destructive) {
                        onDeleteManual()
                    } label: {
                        Label("Delete Manual Entry", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(12)
        .background(DesignSystem.Colors.surface, in: RoundedRectangle(cornerRadius: 10))
    }

    private var confidenceBadge: some View {
        Text("\(result.confidence)%")
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(confidenceColor.opacity(0.18), in: Capsule())
            .foregroundStyle(confidenceColor)
    }

    private var confidenceColor: Color {
        switch result.confidence {
        case 75...: return .green
        case 50..<75: return .orange
        default: return .red
        }
    }
}

private struct TransferImpactRowView: View {
    let row: TransferRequirementsImpactRow

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.alreadySatisfied ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(row.alreadySatisfied ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.targetCourseCode).font(.body.weight(.semibold))
                Text(row.requirementDisplayTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(row.bucket.displayName)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(row.creditsApplied) cr")
                .font(.caption.weight(.semibold))
        }
        .padding(10)
        .background(DesignSystem.Colors.surface, in: RoundedRectangle(cornerRadius: 8))
    }
}
