// AssistantSettingsKey.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantSettingsKey.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Whitelist for `updateAppSetting` writes (cosmetic / preference only).
enum AssistantSettingsKey: String, CaseIterable, Sendable {
    case responseLengthPreset = "assistant.response.lengthPreset"
    case streamingEnabled = "assistant.streaming.enabled"
    case semanticCatalogSearch = "assistant.catalog.semanticSearchEnabled"
    case showDiagnostics = "assistant.runtime.showDiagnostics"
    case appAppearance = "appAppearance"
    case reduceMotion = "ui.reduceMotion"
    case calendarWeekStart = "calendar.weekStartsOnMonday"

    var displayLabel: String {
        switch self {
        case .responseLengthPreset: return "Response length"
        case .streamingEnabled: return "Stream responses"
        case .semanticCatalogSearch: return "Semantic catalog search"
        case .showDiagnostics: return "Show diagnostics"
        case .appAppearance: return "Appearance theme"
        case .reduceMotion: return "Reduce motion"
        case .calendarWeekStart: return "Week starts on Monday"
        }
    }

    var confirmationStyle: AssistantConfirmationStyle { .card }

    static func isWritable(key: String) -> Bool {
        Self(rawValue: key) != nil
    }

    /// Keys the assistant may read for explanations (superset of writable).
    static func isReadable(key: String) -> Bool {
        if isWritable(key: key) { return true }
        let readOnly: Set<String> = [
            AssistantPlannerIndexingSettings.indexingEnabledKey,
            AssistantPlannerIndexingSettings.documentsIndexingKey,
            AssistantInferenceSettings.preferFoundationModelsKey,
            "assistant.localLLM.enabled",
        ]
        return readOnly.contains(key)
    }

    static func rejectedWriteReason(for key: String) -> String? {
        if isWritable(key: key) { return nil }
        let blocked: [String: String] = [
            AssistantPlannerIndexingSettings.indexingEnabledKey: "Planner indexing is controlled in AI & Privacy with consent.",
            AssistantPlannerIndexingSettings.documentsIndexingKey: "Document indexing is controlled in AI & Privacy.",
            AssistantWebSearchSettings.searxBaseURLKey: "SearXNG URL cannot be changed via the assistant.",
            AssistantWebSearchSettings.extraFetchHostsKey: "Fetch hosts cannot be changed via the assistant.",
            "assistant.localLLM.enabled": "Local model settings must be changed in Settings.",
            "security.encryptionEnabled": "Security settings cannot be changed via the assistant.",
        ]
        return blocked[key] ?? "That setting cannot be changed via the assistant."
    }
}
