// VaultShareBundleService.swift
// Feature: Core
// Purpose: Core module — VaultBundleItem.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import AppKit

// MARK: - VaultBundleItem

public struct VaultBundleItem: Sendable {
    public let url: URL
    public let displayName: String

    public init(url: URL, displayName: String) {
        self.url = url
        self.displayName = displayName
    }
}

// MARK: - VaultShareBundleService

enum VaultShareBundleService {

    // MARK: - Bundle Creation

    /// Copies all items into a temp folder and zips it with ditto.
    /// Returns the URL of the resulting zip file.
    static func createBundle(items: [VaultBundleItem], bundleName: String) async throws -> URL {
        try await BackgroundServiceOnDemand.runThrowing(id: "vault_share_bundle") {
            try await createBundleImpl(items: items, bundleName: bundleName)
        }
    }

    private static func createBundleImpl(items: [VaultBundleItem], bundleName: String) async throws -> URL {
        let fm = FileManager.default
        let bundleFolder = fm.temporaryDirectory
            .appendingPathComponent("College-Bundle-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: bundleFolder, withIntermediateDirectories: true)

        for item in items {
            let ext = item.url.pathExtension
            let filename = ext.isEmpty ? item.displayName : "\(item.displayName).\(ext)"
            let dest = bundleFolder.appendingPathComponent(filename)
            try fm.copyItem(at: item.url, to: dest)
        }

        let safeZipName = bundleName
            .components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: "-_ ")).inverted)
            .joined()
        let zipURL = fm.temporaryDirectory.appendingPathComponent("\(safeZipName).zip")

        if fm.fileExists(atPath: zipURL.path) {
            try fm.removeItem(at: zipURL)
        }

        try runDitto(source: bundleFolder, destination: zipURL)

        // Clean up the staging folder
        try? fm.removeItem(at: bundleFolder)

        return zipURL
    }

    // MARK: - Sharing

    /// Creates the bundle zip and presents an NSSharingServicePicker on the main thread.
    static func shareBundle(items: [VaultBundleItem], bundleName: String) async {
        do {
            let zipURL = try await createBundle(items: items, bundleName: bundleName)

            await MainActor.run {
                let picker = NSSharingServicePicker(items: [zipURL])
                let view = NSApp.keyWindow?.contentView ?? NSView()
                picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
            }
        } catch {
            await AppNotificationCenter.shared.post(
                kind: .error,
                title: "Share Failed",
                message: error.localizedDescription
            )
        }
    }

    // MARK: - Ditto Helper

    /// Synchronously zips `source` into `destination` using `/usr/bin/ditto`.
    static func runDitto(source: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [
            "-c", "-k", "--sequesterRsrc", "--keepParent",
            source.path,
            destination.path
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
            throw BundleError.dittoFailed(status: process.terminationStatus, message: errMsg)
        }
    }

    // MARK: - Errors

    enum BundleError: LocalizedError {
        case dittoFailed(status: Int32, message: String)

        var errorDescription: String? {
            switch self {
            case .dittoFailed(let status, let message):
                return "ditto exited with status \(status): \(message)"
            }
        }
    }
}
