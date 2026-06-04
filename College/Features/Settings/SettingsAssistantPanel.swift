// SettingsAssistantPanel.swift
// Feature: Settings
// Purpose: Settings module — SettingsAssistantPanel.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import AppKit
import Combine
import Darwin.Mach
import Observation

struct SettingsAssistantPanel: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var collegePersistence: CollegePersistence

    @StateObject private var aiStorageVM = AIStorageViewModel()
    @State private var runtimeDiagnostics = SettingsRuntimeDiagnosticsModel()
    @State private var selectedModelSpec: ModelSpec = .jsonWorker
    @State private var aiModelErrorText: String?
    @AppStorage(AssistantWebSearchSettings.searxBaseURLKey) private var searxBaseURL: String = AssistantWebSearchSettings.defaultSearxBaseURL
    @AppStorage(AssistantWebSearchSettings.extraFetchHostsKey) private var extraFetchHostsRaw: String = ""
    @AppStorage(AssistantWebSearchSettings.semanticMemoryEnabledKey) private var semanticWebMemoryEnabled: Bool = false
    @AppStorage("assistant.streaming.enabled") private var assistantStreamingEnabled: Bool = true
    @AppStorage("assistant.runtime.showDiagnostics") private var assistantRuntimeDiagnosticsEnabled: Bool = false
    @AppStorage("assistant.response.lengthPreset") private var assistantResponseLengthPreset: String = "balanced"
    @State private var searxValidationMessage: String?
    @State private var isValidatingSearx: Bool = false
    @State private var showAdvancedWebSearchSettings: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsCard(title: "Model", icon: "cpu", iconColor: DesignSystem.Colors.secondary) {
                aiModelRow

                Divider()
                    .overlay(Color(nsColor: .separatorColor).opacity(0.5))

                modelStatusRow

                Divider()
                    .overlay(Color(nsColor: .separatorColor).opacity(0.5))

                modelActionsRow
            }
            .task { await refreshSelectedModelStorage() }
            .onChange(of: selectedModelSpec) { _, _ in
                Task { await refreshSelectedModelStorage() }
            }

            SettingsCard(title: "Web search & memory", icon: "globe", iconColor: DesignSystem.Colors.info) {
                assistantWebSearchSettingsBlock
            }

            SettingsCard(title: "Runtime diagnostics", icon: "gauge.with.dots.needle.33percent", iconColor: .teal) {
                runtimeDiagnosticsBlock
            }
        }
        .frame(maxWidth: SettingsMetrics.detailMaxWidth, alignment: .leading)
        .onAppear {
            Task { await refreshSelectedModelStorage() }
            runtimeDiagnostics.startRefreshing(collegePersistence: collegePersistence)
        }
        .onDisappear {
            runtimeDiagnostics.stopRefreshing()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await refreshSelectedModelStorage() }
            runtimeDiagnostics.refreshOnce(collegePersistence: collegePersistence)
        }
    }

    private var runtimeDiagnosticsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            runtimeDiagnosticsRow(label: "Resident memory", value: runtimeDiagnostics.residentMemoryLabel)
            Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))
            runtimeDiagnosticsRow(label: "LLM loaded", value: runtimeDiagnostics.llmLoadedLabel)
            Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))
            runtimeDiagnosticsRow(label: "Last LLM idle release", value: runtimeDiagnostics.llmIdleReleaseLabel)
            Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))
            runtimeDiagnosticsRow(label: "Last embed idle release", value: runtimeDiagnostics.embedIdleReleaseLabel)
            Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))
            runtimeDiagnosticsRow(label: "Active catalog store", value: runtimeDiagnostics.catalogStorePath, monospaced: true)
            Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))
            runtimeDiagnosticsRow(label: "Last memory pressure", value: runtimeDiagnostics.lastMemoryPressureLabel)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func runtimeDiagnosticsRow(label: String, value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textMain)
                .frame(width: 168, alignment: .leading)
            Text(value)
                .font(DesignSystem.Fonts.main(size: monospaced ? 11 : 13))
                .foregroundColor(DesignSystem.Colors.textLight)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - AI Model Row

    private var aiModelRow: some View {
        let spec = selectedModelSpec
        let sizeLabel = aiStorageVM.installedSizeBytes > 0
            ? aiStorageVM.formatBytes(aiStorageVM.installedSizeBytes)
            : "—"
        let descriptorSuffix = aiStorageVM.hasStaleInstallFiles ? " (outdated files detected)" : ""
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Syllabus AI Model")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textMain)
                Text("\(spec.displayName) · \(sizeLabel)\(descriptorSuffix)")
                    .font(DesignSystem.Fonts.main(size: 11))
                    .foregroundColor(DesignSystem.Colors.textLight)
            }
            Spacer()
            Menu(spec.displayName) {
                Button(ModelSpec.jsonWorker.displayName) {
                    selectedModelSpec = .jsonWorker
                }
            }
            .font(DesignSystem.Fonts.main(size: 12))
            .frame(maxWidth: 180)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - Model Status Row

    private var modelStatusRow: some View {
        let isInstalled = aiStorageVM.isInstalled
        let hasStale = aiStorageVM.hasStaleInstallFiles
        return HStack {
            Text("Model Status")
                .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textMain)
            Spacer()
            Circle()
                .fill(isInstalled ? Color.green : (hasStale ? DesignSystem.Colors.warning : Color.orange))
                .frame(width: 7, height: 7)
            Text(isInstalled ? "Installed" : (hasStale ? "Outdated - Re-download Required" : "Not Installed"))
                .font(DesignSystem.Fonts.main(size: 13))
                .foregroundColor(DesignSystem.Colors.textLight)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - Assistant Web Search & Memory

    private var assistantWebSearchSettingsBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Assistant Web Search")
                .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textMain)

            Text("Default search: Startpage (configured automatically).")
                .font(DesignSystem.Fonts.main(size: 11))
                .foregroundColor(DesignSystem.Colors.textLight)

            DisclosureGroup("Advanced web search settings", isExpanded: $showAdvancedWebSearchSettings) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("SearXNG base URL (HTTPS or localhost HTTP)", text: $searxBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .font(DesignSystem.Fonts.main(size: 12))

                    Text("Default: \(AssistantWebSearchSettings.defaultSearxBaseURL) (Startpage engine). Local dev allowed via http://127.0.0.1:PORT.")
                        .font(DesignSystem.Fonts.main(size: 11))
                        .foregroundColor(DesignSystem.Colors.textLight)

                    HStack(spacing: 12) {
                        Button(isValidatingSearx ? "Validating…" : "Validate SearXNG") {
                            searxValidationMessage = nil
                            isValidatingSearx = true
                            Task {
                                do {
                                    try await SearXNGClient().validateConfiguration()
                                    await MainActor.run {
                                        searxValidationMessage = "Connection OK."
                                        isValidatingSearx = false
                                    }
                                } catch {
                                    await MainActor.run {
                                        searxValidationMessage = error.localizedDescription
                                        isValidatingSearx = false
                                    }
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isValidatingSearx || searxBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }

            if let searxValidationMessage, !searxValidationMessage.isEmpty {
                Text(searxValidationMessage)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                    .foregroundColor(searxValidationMessage.contains("OK") ? DesignSystem.Colors.info : DesignSystem.Colors.error)
            }

            Text("Extra fetch hosts (comma-separated)")
                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textMain)
                .padding(.top, 4)

            TextField("e.g. www.example.edu, example.org", text: $extraFetchHostsRaw)
                .textFieldStyle(.roundedBorder)
                .font(DesignSystem.Fonts.main(size: 12))

            SToggleRow(
                label: "Semantic web memory",
                subtitle: "Stores compact on-device vectors for hybrid retrieval with your message (FTS + cosine). Uses a fast lexical sketch until a dedicated MLX embedding model is added.",
                isOn: $semanticWebMemoryEnabled
            )

            Divider()
                .overlay(Color(nsColor: .separatorColor).opacity(0.5))

            SToggleRow(
                label: "Stream assistant replies",
                subtitle: "Animate local model replies as they arrive in the chat transcript.",
                isOn: $assistantStreamingEnabled
            )

            Divider()
                .overlay(Color(nsColor: .separatorColor).opacity(0.5))

            SToggleRow(
                label: "Assistant runtime diagnostics",
                subtitle: "Show local token/length diagnostics in the assistant transcript footer.",
                isOn: $assistantRuntimeDiagnosticsEnabled
            )

            Divider()
                .overlay(Color(nsColor: .separatorColor).opacity(0.5))

            SMenuRow(
                label: "Assistant response length",
                subtitle: "Controls max local reply size before rendering.",
                currentDisplay: assistantResponseLengthLabel,
                options: ["short", "balanced", "detailed"],
                optionLabel: { value in
                    switch value {
                    case "short": return "Short"
                    case "detailed": return "Detailed"
                    default: return "Balanced"
                    }
                },
                onSelect: { value in
                    assistantResponseLengthPreset = value
                }
            )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var assistantResponseLengthLabel: String {
        switch assistantResponseLengthPreset {
        case "short":
            return "Short"
        case "detailed":
            return "Detailed"
        default:
            return "Balanced"
        }
    }

    // MARK: - Model Actions Row

    private var modelActionsRow: some View {
        let isInstalled = aiStorageVM.isInstalled
        let hasLocalFiles = aiStorageVM.installedSizeBytes > 0
        let hasStale = aiStorageVM.hasStaleInstallFiles
        return VStack(alignment: .leading, spacing: 10) {
            if aiStorageVM.isWorking {
                VStack(alignment: .leading, spacing: 6) {
                    Text(aiStorageVM.detail)
                        .font(DesignSystem.Fonts.main(size: 12))
                        .foregroundColor(DesignSystem.Colors.textLight)
                    ProgressView(value: aiStorageVM.progress)
                        .progressViewStyle(.linear)
                }
            }

            if let aiModelErrorText {
                Text(aiModelErrorText)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.error)
            }

            if hasStale {
                Text("Existing model files do not match the current model spec. Use Repair Download to refresh.")
                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.warning)
            }

            HStack(spacing: 12) {
                Button(isInstalled ? "Re-Download" : (hasStale ? "Repair Download" : "Download")) {
                    Task { await installSelectedModel() }
                }
                .buttonStyle(.plain)
                .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.primary)
                .disabled(aiStorageVM.isWorking)

                if hasLocalFiles {
                    Button("Delete Model") {
                        Task { await deleteSelectedModel() }
                    }
                    .buttonStyle(.plain)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.error)
                    .disabled(aiStorageVM.isWorking)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    @MainActor
    private func refreshSelectedModelStorage() async {
        aiModelErrorText = nil
        await aiStorageVM.refreshSize(for: selectedModelSpec)
    }

    @MainActor
    private func installSelectedModel() async {
        aiModelErrorText = nil
        do {
            try await aiStorageVM.ensureInstalled(spec: selectedModelSpec)
            await aiStorageVM.refreshSize(for: selectedModelSpec)
            UserDefaults.standard.set(true, forKey: "assistant.localLLM.enabled")
            AppNotificationCenter.shared.post(
                kind: .success,
                title: "Model Installed",
                message: "\(selectedModelSpec.displayName) is ready."
            )
        } catch {
            aiModelErrorText = "Install failed: \(error.localizedDescription)"
            AppNotificationCenter.shared.post(
                kind: .error,
                title: "Model Install Failed",
                message: error.localizedDescription
            )
        }
    }

    @MainActor
    private func deleteSelectedModel() async {
        aiModelErrorText = nil
        do {
            try await aiStorageVM.delete(spec: selectedModelSpec)
            await aiStorageVM.refreshSize(for: selectedModelSpec)
            AppNotificationCenter.shared.post(
                kind: .info,
                title: "Model Deleted",
                message: "\(selectedModelSpec.displayName) was removed."
            )
        } catch {
            aiModelErrorText = "Delete failed: \(error.localizedDescription)"
            AppNotificationCenter.shared.post(
                kind: .error,
                title: "Model Delete Failed",
                message: error.localizedDescription
            )
        }
    }
}

// MARK: - Runtime diagnostics (Settings Assistant)

@Observable
@MainActor
final class SettingsRuntimeDiagnosticsModel {
    private(set) var residentMemoryLabel = "—"
    private(set) var llmLoadedLabel = "—"
    private(set) var llmIdleReleaseLabel = "—"
    private(set) var embedIdleReleaseLabel = "—"
    private(set) var catalogStorePath = "—"
    private(set) var lastMemoryPressureLabel = "—"

    private var timerCancellable: AnyCancellable?

    func startRefreshing(collegePersistence: CollegePersistence) {
        stopRefreshing()
        refreshOnce(collegePersistence: collegePersistence)
        timerCancellable = Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshOnce(collegePersistence: collegePersistence)
            }
    }

    func stopRefreshing() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    func refreshOnce(collegePersistence: CollegePersistence) {
        residentMemoryLabel = String(format: "%.1f MB", Self.residentMemoryMB())
        llmIdleReleaseLabel = Self.format(date: LLMMemoryLifecycle.shared.lastIdleReleaseAt)
        embedIdleReleaseLabel = Self.format(date: CatalogEmbedMemoryLifecycle.shared.lastIdleReleaseAt)
        catalogStorePath = Self.activeCatalogStorePath(collegePersistence: collegePersistence)
        lastMemoryPressureLabel = PerformanceDiagnostics.lastMemoryPressureEventDescription()
        Task {
            let loaded = await LocalLLMRunner.shared.isLoaded
            await MainActor.run {
                llmLoadedLabel = loaded ? "Yes" : "No"
            }
        }
    }

    private static func format(date: Date?) -> String {
        guard let date else { return "Never" }
        return date.formatted(date: .abbreviated, time: .standard)
    }

    private static func residentMemoryMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPtr, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return 0 }
        return Double(info.resident_size) / 1_048_576.0
    }

    private static func activeCatalogStorePath(collegePersistence: CollegePersistence) -> String {
        if let schoolID = AppDataStore.shared.activeCatalogSchoolID {
            return CollegeModelContainerFactory.catalogStoreURL(for: schoolID).path
        }
        if let uniName = collegePersistence.getActiveUniversity()?.name {
            let schoolID = CatalogStoreCoordinator.shared.schoolID(for: uniName)
            return CatalogStoreCoordinator.shared.localStoreStoreURL(for: schoolID).path
        }
        return "—"
    }
}
