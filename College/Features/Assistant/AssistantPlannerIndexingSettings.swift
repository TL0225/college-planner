// AssistantPlannerIndexingSettings.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantPlannerIndexingSettings.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// UserDefaults keys for on-device planner indexing consent and toggles.
enum AssistantPlannerIndexingSettings: Sendable {
    static let indexingEnabledKey = "assistant.planner.indexingEnabled"
    static let consentPresentedKey = "assistant.planner.consentPresented"
    static let documentsIndexingKey = "assistant.planner.documentsIndexingEnabled"
    static let indexReadyKey = "assistant.planner.indexReady"
    static let lastIndexedAtKey = "assistant.planner.lastIndexedAt"
    static let lastChunkCountKey = "assistant.planner.lastChunkCount"

    static var isIndexingEnabled: Bool {
        UserDefaults.standard.bool(forKey: indexingEnabledKey)
    }

    static var isDocumentsIndexingEnabled: Bool {
        guard isIndexingEnabled else { return false }
        if UserDefaults.standard.object(forKey: documentsIndexingKey) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: documentsIndexingKey)
    }

    static var hasPresentedConsent: Bool {
        UserDefaults.standard.bool(forKey: consentPresentedKey)
    }

    static var indexReady: Bool {
        UserDefaults.standard.bool(forKey: indexReadyKey)
    }

    static func enableIndexing(documentsDefaultOn: Bool = true) {
        UserDefaults.standard.set(true, forKey: indexingEnabledKey)
        UserDefaults.standard.set(true, forKey: consentPresentedKey)
        if UserDefaults.standard.object(forKey: documentsIndexingKey) == nil {
            UserDefaults.standard.set(documentsDefaultOn, forKey: documentsIndexingKey)
        }
    }

    static func disableIndexing() {
        UserDefaults.standard.set(false, forKey: indexingEnabledKey)
    }

    static func markIndexed(chunkCount: Int) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastIndexedAtKey)
        UserDefaults.standard.set(max(0, chunkCount), forKey: lastChunkCountKey)
        if chunkCount > 0 {
            UserDefaults.standard.set(true, forKey: indexReadyKey)
        }
    }

    /// Last known chunk count for UI (avoids a false "indexing…" flash before async refresh).
    static var cachedChunkCount: Int {
        if UserDefaults.standard.object(forKey: lastChunkCountKey) != nil {
            return max(0, UserDefaults.standard.integer(forKey: lastChunkCountKey))
        }
        if indexReady {
            return PlannerVectorSearchConfig.usefulnessChunkFloor
        }
        return 0
    }

    static func clearIndexedState() {
        UserDefaults.standard.set(false, forKey: indexReadyKey)
        UserDefaults.standard.removeObject(forKey: lastChunkCountKey)
    }

    static var lastIndexedDescription: String {
        let ts = UserDefaults.standard.double(forKey: lastIndexedAtKey)
        guard ts > 0 else { return "Never" }
        let date = Date(timeIntervalSince1970: ts)
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }

    /// UI tests: `--uitest-planner-indexing-consent=1` enables indexing without sheet.
    static func applyUITestOverridesIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--uitest-planner-indexing-consent=1") {
            enableIndexing()
        }
        if args.contains("--uitest-skip-consent-sheet") {
            UserDefaults.standard.set(true, forKey: consentPresentedKey)
        }
    }

    static var shouldPresentConsentSheet: Bool {
        applyUITestOverridesIfNeeded()
        if ProcessInfo.processInfo.arguments.contains("--uitest-skip-consent-sheet") {
            return false
        }
        return !hasPresentedConsent && !isIndexingEnabled
    }
}
