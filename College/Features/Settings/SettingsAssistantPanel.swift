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
    @Environment(AppContainer.self) private var container
    private var persistence: CollegePersistence { container.persistence }
    @Environment(\.scenePhase) private var scenePhase
    private var collegePersistence: CollegePersistence { container.persistence }
    @StateObject private var aiStorageVM = AIStorageViewModel()
    @State private var runtimeDiagnostics = SettingsRuntimeDiagnosticsModel()
    @State private var selectedModelSpec: ModelSpec = .jsonWorker
    @State private var aiModelErrorText: String?
    @AppStorage(AssistantWebSearchSettings.webSearchEnabledKey) private var webSearchEnabled: Bool = true
    @AppStorage(AssistantWebSearchSettings.customBaseURLKey) private var customWebSearchBaseURL: String = ""
    @AppStorage(AssistantWebSearchSettings.extraFetchHostsKey) private var extraFetchHostsRaw: String = ""
    @AppStorage(AssistantWebSearchSettings.semanticMemoryEnabledKey) private var semanticWebMemoryEnabled: Bool = false
    @AppStorage("assistant.streaming.enabled") private var assistantStreamingEnabled: Bool = true
    @AppStorage("assistant.runtime.showDiagnostics") private var assistantRuntimeDiagnosticsEnabled: Bool = false
    @AppStorage("assistant.response.lengthPreset") private var assistantResponseLengthPreset: String = "balanced"
    @State private var webSearchValidationMessage: String?
    @State private var isValidatingWebSearch: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsCard(
                title: String(localized: "settings.assistant.model.card_title", defaultValue: "Model"),
                icon: "cpu",
                iconColor: DesignSystem.Colors.secondary
            ) {
                modelRow

                rowDivider

                modelStatusRow

                rowDivider

                modelDownloadRow

                if modelHasLocalFiles {
                    rowDivider
                    modelDeleteRow
                }

                if aiStorageVM.isWorking || aiModelErrorText != nil || aiStorageVM.hasStaleInstallFiles {
                    rowDivider
                    modelActivityBlock
                }
            }
            .task { await refreshSelectedModelStorage() }
            .onChange(of: selectedModelSpec) { _, _ in
                Task { await refreshSelectedModelStorage() }
            }

            SettingsCard(
                title: String(localized: "settings.assistant.websearch.card_title", defaultValue: "Web search & memory"),
                icon: "globe",
                iconColor: DesignSystem.Colors.info
            ) {
                assistantWebSearchSettingsBlock
            }

            SettingsCard(
                title: String(localized: "settings.assistant.diagnostics.card_title", defaultValue: "Runtime diagnostics"),
                icon: "gauge.with.dots.needle.33percent",
                iconColor: .teal
            ) {
                SAdvancedDisclosure(
                    title: String(localized: "settings.assistant.diagnostics.disclosure_title", defaultValue: "Live runtime diagnostics"),
                    subtitle: String(localized: "settings.assistant.diagnostics.disclosure_subtitle", defaultValue: "On-device memory, model, and catalog state")
                ) {
                    runtimeDiagnosticsBlock
                }

                rowDivider

                clearMemoryRow
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

    private var rowDivider: some View {
        Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))
    }

    // MARK: - Runtime diagnostics

    private var runtimeDiagnosticsBlock: some View {
        SettingsRuntimeDiagnosticsView(model: runtimeDiagnostics)
    }

    private var clearMemoryRow: some View {
        SActionRow(
            label: String(localized: "settings.assistant.clear_memory.label", defaultValue: "Clear runtime memory"),
            subtitle: String(localized: "settings.assistant.clear_memory.subtitle", defaultValue: "Release loaded model and embedder weights from RAM."),
            actionLabel: String(localized: "settings.assistant.clear_memory.action", defaultValue: "CLEAR"),
            actionColor: DesignSystem.Colors.warning
        ) {
            clearRuntimeMemory()
        }
    }

    // MARK: - Model rows

    private var modelRow: some View {
        let spec = selectedModelSpec
        let sizeLabel = aiStorageVM.installedSizeBytes > 0
            ? aiStorageVM.formatBytes(aiStorageVM.installedSizeBytes)
            : "—"
        let descriptorSuffix = aiStorageVM.hasStaleInstallFiles
            ? " " + String(localized: "settings.assistant.model.outdated_suffix", defaultValue: "(outdated files detected)")
            : ""
        return SRow(
            label: String(localized: "settings.assistant.model.name_label", defaultValue: "Syllabus AI Model"),
            subtitle: "\(sizeLabel)\(descriptorSuffix)",
            value: spec.displayName
        )
    }

    private var modelStatusRow: some View {
        SRow(
            label: String(localized: "settings.assistant.model.status_label", defaultValue: "Model Status"),
            value: modelStatusText
        )
    }

    private var modelStatusText: String {
        if aiStorageVM.isInstalled {
            return String(localized: "settings.assistant.model.status.installed", defaultValue: "Installed")
        }
        if aiStorageVM.hasStaleInstallFiles {
            return String(localized: "settings.assistant.model.status.outdated", defaultValue: "Outdated - Re-download Required")
        }
        if aiStorageVM.isAutoInstallSuppressed {
            return String(localized: "settings.assistant.model.status.auto_off", defaultValue: "Not Installed - Auto-download Off")
        }
        return String(localized: "settings.assistant.model.status.not_installed", defaultValue: "Not Installed")
    }

    private var modelDownloadActionLabel: String {
        if aiStorageVM.isInstalled {
            return String(localized: "settings.assistant.model.action.redownload", defaultValue: "RE-DOWNLOAD")
        }
        if aiStorageVM.hasStaleInstallFiles {
            return String(localized: "settings.assistant.model.action.repair", defaultValue: "REPAIR")
        }
        return String(localized: "settings.assistant.model.action.download", defaultValue: "DOWNLOAD")
    }

    private var modelDownloadRow: some View {
        SActionRow(
            label: String(localized: "settings.assistant.model.download_label", defaultValue: "Model files"),
            actionLabel: aiStorageVM.isWorking
                ? String(localized: "settings.assistant.model.action.working", defaultValue: "WORKING…")
                : modelDownloadActionLabel
        ) {
            guard !aiStorageVM.isWorking else { return }
            Task { await installSelectedModel() }
        }
    }

    private var modelHasLocalFiles: Bool { aiStorageVM.installedSizeBytes > 0 }

    private var modelDeleteRow: some View {
        SActionRow(
            label: String(localized: "settings.assistant.model.delete_label", defaultValue: "Delete Model"),
            actionLabel: String(localized: "settings.assistant.model.action.delete", defaultValue: "DELETE"),
            actionColor: DesignSystem.Colors.error
        ) {
            guard !aiStorageVM.isWorking else { return }
            Task { await deleteSelectedModel() }
        }
    }

    private var modelActivityBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            if aiStorageVM.isWorking {
                Text(aiStorageVM.detail)
                    .font(DesignSystem.Fonts.main(size: 12))
                    .foregroundStyle(DesignSystem.Colors.textLight)
                ProgressView(value: aiStorageVM.progress)
                    .progressViewStyle(.linear)
            }

            if let aiModelErrorText {
                Text(aiModelErrorText)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.error)
            }

            if aiStorageVM.hasStaleInstallFiles {
                Text(String(localized: "settings.assistant.model.stale_hint", defaultValue: "Existing model files do not match the current model spec. Use Repair to refresh."))
                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.warning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.primary.opacity(0.015))
    }

    // MARK: - Assistant Web Search & Memory

    private var assistantWebSearchSettingsBlock: some View {
        VStack(spacing: 0) {
            SToggleRow(
                label: String(localized: "settings.assistant.websearch.enabled.label", defaultValue: "Web search"),
                subtitle: String(localized: "settings.assistant.websearch.enabled.subtitle", defaultValue: "Uses a built-in local DeGoog instance on 127.0.0.1 — no API keys or Docker."),
                isOn: $webSearchEnabled
            )

            rowDivider

            SToggleRow(
                label: String(localized: "settings.assistant.semantic_memory.label", defaultValue: "Semantic web memory"),
                subtitle: String(localized: "settings.assistant.semantic_memory.subtitle", defaultValue: "Stores compact on-device vectors for hybrid retrieval with your message (FTS + cosine). Uses a fast lexical sketch until a dedicated MLX embedding model is added."),
                isOn: $semanticWebMemoryEnabled
            )

            rowDivider

            SToggleRow(
                label: String(localized: "settings.assistant.streaming.label", defaultValue: "Stream assistant replies"),
                subtitle: String(localized: "settings.assistant.streaming.subtitle", defaultValue: "Animate local model replies as they arrive in the chat transcript."),
                isOn: $assistantStreamingEnabled
            )

            rowDivider

            SToggleRow(
                label: String(localized: "settings.assistant.runtime_diag.label", defaultValue: "Assistant runtime diagnostics"),
                subtitle: String(localized: "settings.assistant.runtime_diag.subtitle", defaultValue: "Show local token/length diagnostics in the assistant transcript footer."),
                isOn: $assistantRuntimeDiagnosticsEnabled
            )

            rowDivider

            SMenuRow(
                label: String(localized: "settings.assistant.response_length.label", defaultValue: "Assistant response length"),
                subtitle: String(localized: "settings.assistant.response_length.subtitle", defaultValue: "Controls max local reply size before rendering."),
                currentDisplay: assistantResponseLengthLabel,
                options: ["short", "balanced", "detailed"],
                optionLabel: { responseLengthLabel(for: $0) },
                onSelect: { assistantResponseLengthPreset = $0 }
            )

            rowDivider

            SAdvancedDisclosure(
                title: String(localized: "settings.assistant.advanced_search.title", defaultValue: "Advanced web search settings"),
                subtitle: String(localized: "settings.assistant.advanced_search.subtitle", defaultValue: "Override the built-in DeGoog URL or tune page-fetch hosts.")
            ) {
                advancedWebSearchContent
            }
        }
    }

    private var advancedWebSearchContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "settings.assistant.degoog.field_label", defaultValue: "Custom DeGoog base URL"))
                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textMain)

                TextField(
                    String(localized: "settings.assistant.degoog.field_placeholder", defaultValue: "Leave empty for built-in search (http://127.0.0.1:\(CollegeWebSearchDefaults.port))"),
                    text: $customWebSearchBaseURL
                )
                .textFieldStyle(.roundedBorder)
                .font(DesignSystem.Fonts.main(size: 12))

                Text(String(localized: "settings.assistant.degoog.field_help", defaultValue: "Optional. HTTPS or localhost HTTP only. Empty uses the bundled sidecar automatically."))
                    .font(DesignSystem.Fonts.main(size: 11))
                    .foregroundStyle(DesignSystem.Colors.textLight)
            }

            Button(isValidatingWebSearch
                ? String(localized: "settings.assistant.degoog.validating", defaultValue: "Validating…")
                : String(localized: "settings.assistant.degoog.validate", defaultValue: "Validate web search")
            ) {
                validateWebSearch()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isValidatingWebSearch || !webSearchEnabled)

            if let webSearchValidationMessage, !webSearchValidationMessage.isEmpty {
                Text(webSearchValidationMessage)
                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                    .foregroundStyle(webSearchValidationMessage.contains("OK") ? DesignSystem.Colors.info : DesignSystem.Colors.error)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "settings.assistant.extra_hosts.label", defaultValue: "Extra fetch hosts (comma-separated)"))
                    .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textMain)

                TextField(
                    String(localized: "settings.assistant.extra_hosts.placeholder", defaultValue: "e.g. www.example.edu, example.org"),
                    text: $extraFetchHostsRaw
                )
                .textFieldStyle(.roundedBorder)
                .font(DesignSystem.Fonts.main(size: 12))
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func responseLengthLabel(for value: String) -> String {
        switch value {
        case "short":    return String(localized: "settings.assistant.response_length.short", defaultValue: "Short")
        case "detailed": return String(localized: "settings.assistant.response_length.detailed", defaultValue: "Detailed")
        default:         return String(localized: "settings.assistant.response_length.balanced", defaultValue: "Balanced")
        }
    }

    private var assistantResponseLengthLabel: String {
        responseLengthLabel(for: assistantResponseLengthPreset)
    }

    // MARK: - Actions

    private func validateWebSearch() {
        webSearchValidationMessage = nil
        isValidatingWebSearch = true
        Task {
            do {
                try await DeGoogSearchClient().validateConfiguration()
                await MainActor.run {
                    webSearchValidationMessage = String(localized: "settings.assistant.degoog.connection_ok", defaultValue: "Connection OK.")
                    isValidatingWebSearch = false
                }
            } catch {
                await MainActor.run {
                    webSearchValidationMessage = error.localizedDescription
                    isValidatingWebSearch = false
                }
            }
        }
    }

    @MainActor
    private func clearRuntimeMemory() {
        LLMMemoryLifecycle.shared.releaseNow()
        CatalogEmbedMemoryLifecycle.shared.releaseNow()
        runtimeDiagnostics.refreshOnce(collegePersistence: collegePersistence)
        AppNotificationCenter.shared.post(
            kind: .info,
            title: String(localized: "settings.assistant.clear_memory.toast_title", defaultValue: "Runtime Memory Cleared"),
            message: String(localized: "settings.assistant.clear_memory.toast_message", defaultValue: "Loaded model and embedder weights were released from memory.")
        )
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
                title: String(localized: "settings.assistant.model.installed_title", defaultValue: "Model Installed"),
                message: String(localized: "settings.assistant.model.installed_message", defaultValue: "\(selectedModelSpec.displayName) is ready.")
            )
        } catch {
            aiModelErrorText = String(localized: "settings.assistant.model.install_failed", defaultValue: "Install failed: \(error.localizedDescription)")
            AppNotificationCenter.shared.post(
                kind: .error,
                title: String(localized: "settings.assistant.model.install_failed_title", defaultValue: "Model Install Failed"),
                message: error.localizedDescription
            )
        }
    }

    @MainActor
    private func deleteSelectedModel() async {
        aiModelErrorText = nil
        do {
            await LocalLLMRunner.shared.releaseModel()
            try await aiStorageVM.delete(spec: selectedModelSpec)
            await aiStorageVM.refreshSize(for: selectedModelSpec)
            UserDefaults.standard.set(false, forKey: "assistant.localLLM.enabled")
            AppNotificationCenter.shared.post(
                kind: .info,
                title: String(localized: "settings.assistant.model.deleted_title", defaultValue: "Model Deleted"),
                message: String(localized: "settings.assistant.model.deleted_message", defaultValue: "\(selectedModelSpec.displayName) was removed.")
            )
        } catch {
            aiModelErrorText = String(localized: "settings.assistant.model.delete_failed", defaultValue: "Delete failed: \(error.localizedDescription)")
            AppNotificationCenter.shared.post(
                kind: .error,
                title: String(localized: "settings.assistant.model.delete_failed_title", defaultValue: "Model Delete Failed"),
                message: error.localizedDescription
            )
        }
    }
}

// MARK: - Runtime diagnostics (Settings Assistant)

@Observable
@MainActor
final class SettingsRuntimeDiagnosticsModel {
    private(set) var footprintMemoryLabel = "—"
    private(set) var residentMemoryLabel = "—"
    private(set) var mlxMemoryLabel = "—"
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
        footprintMemoryLabel = String(format: "%.1f MB", PerformanceDiagnostics.footprintMemoryMB())
        residentMemoryLabel = String(format: "%.1f MB", PerformanceDiagnostics.residentMemoryMB())
        mlxMemoryLabel = Self.mlxMemoryDescription()
        llmIdleReleaseLabel = Self.format(date: LLMMemoryLifecycle.shared.lastIdleReleaseAt)
        embedIdleReleaseLabel = Self.format(date: CatalogEmbedMemoryLifecycle.shared.lastIdleReleaseAt)
        catalogStorePath = Self.activeCatalogStorePath(collegePersistence: collegePersistence)
        lastMemoryPressureLabel = PerformanceDiagnostics.lastMemoryPressureEventDescription()
        Task {
            let loaded = await LocalLLMRunner.shared.isLoaded
            await MainActor.run {
                llmLoadedLabel = loaded
                    ? String(localized: "settings.assistant.diagnostics.value_yes", defaultValue: "Yes")
                    : String(localized: "settings.assistant.diagnostics.value_no", defaultValue: "No")
            }
        }
    }

    private static func format(date: Date?) -> String {
        guard let date else {
            return String(localized: "settings.assistant.diagnostics.value_never", defaultValue: "Never")
        }
        return date.formatted(date: .abbreviated, time: .standard)
    }

    /// Active (live arrays) + cache (parked reuse buffers) held by MLX's Metal allocator.
    /// Reads as "Not used this session" until a model/embedder has actually run, so it never
    /// forces Metal to initialize just to populate the diagnostics panel.
    private static func mlxMemoryDescription() -> String {
        guard MLXRuntimeMemory.wasInitialized else {
            return String(localized: "settings.assistant.diagnostics.mlx_unused", defaultValue: "Not used this session")
        }
        let active = Double(MLXRuntimeMemory.activeBytes) / 1_048_576.0
        let cache = Double(MLXRuntimeMemory.cacheBytes) / 1_048_576.0
        return String(format: "%.1f MB active · %.1f MB cache", active, cache)
    }

    private static func activeCatalogStorePath(collegePersistence: CollegePersistence) -> String {
        _ = collegePersistence
        return CollegeModelContainerFactory.unifiedStoreURL().path
    }
}
