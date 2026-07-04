// DiagnosticsStorageMigration.swift
// Feature: Debug
// Purpose: One-time migration of large UserDefaults diagnostic blobs to JSON files.

import Foundation

enum DiagnosticsStorageMigration {
    private static let versionKey = "diagnostics.storageMigration.version"
    private static let currentVersion = 1

    static func runIfNeeded() async {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: versionKey) < currentVersion else { return }
        guard let reportsDir = DiagnosticsArtifacts.migratedReportsDirectory(create: true) else { return }

        await migratePrefix("catalog.pdf.scrapeReport.v1.", to: reportsDir, name: "pdf-scrape")
        await migratePrefix("catalog.integrity.report.v1.", to: reportsDir, name: "integrity")
        await migrateScalarKey("catalog.ingest.observability.v1", to: reportsDir, name: "ingest-observability.json")
        await migrateScalarKey("catalog.review.queue.v1", to: reportsDir, name: "review-queue.json")

        defaults.set(currentVersion, forKey: versionKey)
    }

    private static func migratePrefix(_ prefix: String, to dir: URL, name: String) async {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            guard let data = defaults.data(forKey: key) ?? defaults.string(forKey: key)?.data(using: .utf8) else { continue }
            let suffix = key.replacingOccurrences(of: prefix, with: "").replacingOccurrences(of: ".", with: "_")
            let url = dir.appendingPathComponent("\(name)-\(suffix).json")
            if !FileManager.default.fileExists(atPath: url.path) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private static func migrateScalarKey(_ key: String, to dir: URL, name: String) async {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: key) ?? defaults.string(forKey: key)?.data(using: .utf8) else { return }
        let url = dir.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
