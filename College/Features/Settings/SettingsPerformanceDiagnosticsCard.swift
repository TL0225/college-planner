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

    var body: some View {
        SettingsCard(title: "Performance Diagnostics", icon: "gauge.with.dots.needle.33percent", iconColor: .teal) {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    diagnosticRow("Resident memory", String(format: "%.1f MB", PerformanceDiagnostics.residentMemoryMB()))
                    diagnosticRow("CPU", String(format: "%.1f%%", performanceMonitor.cpuPercent))
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
                    Text(PerformanceDiagnostics.activeCatalogStorePathDescription())
                        .font(DesignSystem.Fonts.main(size: 11))
                        .foregroundColor(DesignSystem.Colors.textLight)
                        .lineLimit(3)
                }
                .padding(.top, 8)
            } label: {
                Text("Runtime snapshot")
                    .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textMain)
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                performanceMonitor.start()
                refreshLLMState()
            } else {
                performanceMonitor.stop()
            }
        }
        .task(id: isExpanded) {
            guard isExpanded else { return }
            while !Task.isCancelled {
                refreshLLMState()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func diagnosticRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(DesignSystem.Fonts.main(size: 12, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textLight)
            Spacer()
            Text(value)
                .font(DesignSystem.Fonts.main(size: 12))
                .foregroundColor(DesignSystem.Colors.textMain)
        }
    }

    private func refreshLLMState() {
        Task {
            let loaded = await LocalLLMRunner.shared.isLoaded
            let installed = await ModelManager.shared.isModelInstalled(.jsonWorker)
            await MainActor.run {
                llmLoaded = loaded
                jsonWorkerInstalled = installed
            }
        }
    }
}
