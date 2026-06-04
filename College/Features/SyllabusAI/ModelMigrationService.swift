// ModelMigrationService.swift
// Feature: SyllabusAI
// Purpose: SyllabusAI module — ModelMigrationService.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// One-time launch migrations for on-device model installs and assistant message persistence.
enum ModelMigrationService {
    private static let gemmaPurgeCompletedKey = "college.modelMigration.gemma4_4bit.purged.v1"
    private static let assistantVisionStripCompletedKey = "college.modelMigration.assistant.visionURLs.stripped.v1"
    private static let assistantMessagesStoreKey = "assistant.messages.v1"
    private static let legacyGemmaVariantDirectoryName = "gemma4_4bit"

    static func runLaunchMigrationsIfNeeded() {
        purgeLegacyGemmaInstallIfNeeded()
        stripVisionURLsFromPersistedAssistantMessagesIfNeeded()
    }

    // MARK: - Gemma 4 install directory

    static func purgeLegacyGemmaInstallIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: gemmaPurgeCompletedKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: gemmaPurgeCompletedKey) }

        guard let modelsRoot = try? legacyModelsRootDirectory() else { return }
        let legacyDir = modelsRoot.appendingPathComponent(legacyGemmaVariantDirectoryName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: legacyDir.path) else { return }
        try? FileManager.default.removeItem(at: legacyDir)
    }

    private static func legacyModelsRootDirectory() throws -> URL {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ModelManagerError.fileMoveFailed
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "College"
        return appSupport
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    // MARK: - Assistant persisted messages

    /// Removes legacy `visionImageURLStrings` keys from stored assistant JSON (Gemma vision era).
    static func stripVisionURLsFromPersistedAssistantMessagesIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: assistantVisionStripCompletedKey) else { return }

        if let raw = UserDefaults.standard.string(forKey: assistantMessagesStoreKey),
           let sanitized = sanitizeAssistantMessagesJSON(raw) {
            UserDefaults.standard.set(sanitized, forKey: assistantMessagesStoreKey)
        }

        UserDefaults.standard.set(true, forKey: assistantVisionStripCompletedKey)
    }

    /// Strips vision attachment metadata from a persisted messages JSON blob before decode.
    static func sanitizeAssistantMessagesJSON(_ raw: String) -> String? {
        guard let data = raw.data(using: .utf8),
              var rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !rows.isEmpty else {
            return raw
        }

        var changed = false
        for index in rows.indices {
            if rows[index].removeValue(forKey: "visionImageURLStrings") != nil {
                changed = true
            }
        }
        guard changed,
              let outData = try? JSONSerialization.data(withJSONObject: rows),
              let out = String(data: outData, encoding: .utf8) else {
            return raw
        }
        return out
    }
}
