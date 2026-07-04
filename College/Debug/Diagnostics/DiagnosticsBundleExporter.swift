// DiagnosticsBundleExporter.swift
// Feature: Debug
// Purpose: Tiered redacted diagnostic bundle export via NSSavePanel.

import AppKit
import Foundation
import UniformTypeIdentifiers

enum DiagnosticsBundleExporter {
    struct Result: Sendable {
        let outputURL: URL
        let includedFiles: Int
        let truncationNote: String?
    }

    @MainActor
    static func export(level: DiagnosticsExportLevel) async throws -> Result? {
        let panel = NSSavePanel()
        panel.title = "Export Diagnostics Bundle"
        panel.nameFieldStringValue = "College-Diagnostics-\(level.rawValue)-\(exportTimestamp()).zip"
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return nil }

        return try await export(to: destination, level: level)
    }

    static func export(to destination: URL, level: DiagnosticsExportLevel) async throws -> Result {
        let policy = DiagnosticsExportPolicy.policy(for: level)
        var truncationNote: String?
        let artifactURLs = policy.resolvedURLs(truncationNote: &truncationNote)

        let fm = FileManager.default
        let staging = fm.temporaryDirectory
            .appendingPathComponent("CollegeDiagnostics-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        try await SupportSnapshotGenerator.writeJSON(
            to: staging.appendingPathComponent("support-summary.json"),
            exportNote: truncationNote
        )
        try DiagnosticsEnvironment.writeJSON(to: staging.appendingPathComponent("environment.json"))
        try await MainActor.run {
            try SnowLeopardHealthMetrics.writeJSON(to: staging.appendingPathComponent("snow-leopard-metrics.json"))
        }

        for url in artifactURLs {
            let dest = staging.appendingPathComponent(relativeStagingPath(for: url))
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
            try DiagnosticsExportRedactor.redactedCopy(from: url, to: dest, level: level)
        }

        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try await zipDirectory(staging, to: destination)

        return Result(outputURL: destination, includedFiles: artifactURLs.count + 3, truncationNote: truncationNote)
    }

    private static func relativeStagingPath(for url: URL) -> String {
        let path = url.path
        if path.contains("/Logs/") { return "Logs/\(url.lastPathComponent)" }
        if path.contains("/CrashReports/") { return "CrashReports/\(url.lastPathComponent)" }
        if path.contains("/Diagnostics/") {
            return "Diagnostics/\(url.lastPathComponent)"
        }
        if path.contains("/College/") {
            return "Catalog/\(url.lastPathComponent)"
        }
        return url.lastPathComponent
    }

    private static func exportTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
    }

    private static func zipDirectory(_ source: URL, to destination: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", destination.path, "."]
        process.currentDirectoryURL = source
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "DiagnosticsBundleExporter", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create zip archive."
            ])
        }
    }
}
