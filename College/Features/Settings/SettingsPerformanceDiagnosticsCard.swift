// SettingsPerformanceDiagnosticsCard.swift
// Feature: Settings
// Purpose: Settings module — SettingsPerformanceDiagnosticsCard.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Settings → Privacy: live memory / LLM / catalog diagnostics (Phase 6).
struct SettingsPerformanceDiagnosticsCard: View {
    @State private var performanceMonitor = PerformanceMonitor()
    @State private var isExpanded = false
    @State private var llmLoaded = false
    @State private var jsonWorkerInstalled = false
    @State private var recentLoadOperations: [LoadOperationRecord] = []
    @State private var displayedCPUPercent: Double = 0

    var body: some View {
        SettingsCard(
            title: "Performance Diagnostics",
            icon: "gauge.with.dots.needle.33percent",
            iconColor: .teal,
            contentPadding: DesignSystem.Spacing.md
        ) {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    diagnosticRow("Resident memory", String(format: "%.1f MB", PerformanceDiagnostics.residentMemoryMB()))
                    diagnosticRow("CPU", String(format: "%.1f%%", displayedCPUPercent))
                    diagnosticRow("JSON worker loaded", llmLoaded ? "Yes" : "No")
                    diagnosticRow("Qwen3.5 installed", jsonWorkerInstalled ? "Yes" : "No")
                    diagnosticRow(
                        "LLM idle release",
                        PerformanceDiagnostics.freeMemoryBetweenSessionsEnabled
                            ? "\(PerformanceDiagnostics.llmIdleTimeoutSeconds)s after use"
                            : "Disabled"
                    )
                    diagnosticRow("local store", PerformanceDiagnostics.localStoreDiagnosticsSummary())
                    diagnosticRow("Last memory pressure", PerformanceDiagnostics.lastMemoryPressureEventDescription())
                    diagnosticRow("Translation cache entries", "\(TranslationCache.shared.entryCount)")
                    diagnosticRow("Vault thumbnail cache", "\(VaultThumbnailCache.shared.entryCount)")
                    diagnosticRow("Snow Leopard refreshAll calls", "\(SnowLeopardHealthMetrics.snapshot().refreshAllCallCount)")
                    if !recentLoadOperations.isEmpty {
                        Divider().padding(.vertical, 4)
                        Text("Recent load operations")
                            .font(DesignSystem.Fonts.main(size: 12, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.textMain)
                        ForEach(recentLoadOperations.reversed()) { record in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.summaryLine)
                                    .font(DesignSystem.Fonts.main(size: 11))
                                    .foregroundStyle(record.exceededBudget ? DesignSystem.Colors.warning : DesignSystem.Colors.textMain)
                                if record.peakMainThreadLagMs > 0 {
                                    Text("Main-thread lag peak \(record.peakMainThreadLagMs) ms · \(record.executionContext.rawValue)")
                                        .font(DesignSystem.Fonts.main(size: 10))
                                        .foregroundStyle(DesignSystem.Colors.textLight)
                                }
                            }
                        }
                    }
                    Text(PerformanceDiagnostics.activeCatalogStorePathDescription())
                        .font(DesignSystem.Fonts.main(size: 11))
                        .foregroundStyle(DesignSystem.Colors.textLight)
                        .lineLimit(3)
                }
                .padding(.top, 8)
            } label: {
                Text("Runtime snapshot")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textMain)
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                performanceMonitor.start()
            } else {
                performanceMonitor.stop()
            }
        }
        .task(id: isExpanded) {
            guard isExpanded else { return }
            await Task.yield()
            while !Task.isCancelled {
                await refreshLLMState()
                await refreshLoadOperations()
                displayedCPUPercent = performanceMonitor.cpuPercent
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func diagnosticRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textLight)
            Spacer()
            Text(value)
                .font(DesignSystem.Fonts.main(size: 12))
                .foregroundStyle(DesignSystem.Colors.textMain)
        }
    }

    private func refreshLLMState() async {
        llmLoaded = await LocalLLMRunner.shared.isLoaded
        jsonWorkerInstalled = await ModelManager.shared.isModelInstalled(.jsonWorker)
    }

    private func refreshLoadOperations() async {
        recentLoadOperations = await LoadOperationTrace.recent(limit: 12)
    }
}
