// SettingsRuntimeDiagnosticsView.swift
// Feature: Settings
// Purpose: Reusable live runtime diagnostics rows for Assistant + Diagnostics Center.

import SwiftUI

struct SettingsRuntimeDiagnosticsView: View {
    @Bindable var model: SettingsRuntimeDiagnosticsModel

    var body: some View {
        VStack(spacing: 0) {
            SRow(
                label: String(localized: "settings.assistant.diagnostics.footprint", defaultValue: "Memory footprint"),
                value: model.footprintMemoryLabel,
                valueSelectable: true
            )
            divider
            SRow(
                label: String(localized: "settings.assistant.diagnostics.resident", defaultValue: "Resident (incl. shared)"),
                value: model.residentMemoryLabel,
                valueSelectable: true
            )
            divider
            SRow(
                label: String(localized: "settings.assistant.diagnostics.mlx", defaultValue: "MLX GPU memory"),
                value: model.mlxMemoryLabel,
                valueSelectable: true
            )
            divider
            SRow(
                label: String(localized: "settings.assistant.diagnostics.llm_loaded", defaultValue: "LLM loaded"),
                value: model.llmLoadedLabel,
                valueSelectable: true
            )
            divider
            SRow(
                label: String(localized: "settings.assistant.diagnostics.llm_idle", defaultValue: "Last LLM idle release"),
                value: model.llmIdleReleaseLabel,
                valueSelectable: true
            )
            divider
            SRow(
                label: String(localized: "settings.assistant.diagnostics.embed_idle", defaultValue: "Last embed idle release"),
                value: model.embedIdleReleaseLabel,
                valueSelectable: true
            )
            divider
            SRow(
                label: String(localized: "settings.assistant.diagnostics.catalog_store", defaultValue: "Active catalog store"),
                value: model.catalogStorePath,
                valueSelectable: true
            )
            divider
            SRow(
                label: String(localized: "settings.assistant.diagnostics.last_pressure", defaultValue: "Last memory pressure"),
                value: model.lastMemoryPressureLabel,
                valueSelectable: true
            )
        }
    }

    private var divider: some View {
        Divider().overlay(Color(nsColor: .separatorColor).opacity(0.5))
    }
}
