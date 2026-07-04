// VaultScreenshotTriage.swift
// Feature: Core
// Purpose: Core module — VaultScreenshotTriage.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftUI
import Combine

// MARK: - VaultScreenshotTriage

@MainActor final class VaultScreenshotTriage: ObservableObject {

    static let shared = VaultScreenshotTriage()

    // MARK: Published State

    @Published var pendingScreenshots: [URL] = []
    @Published private(set) var isDailyScanScheduled: Bool = false

    // MARK: App Storage

    @AppStorage("screenshotTriageEnabled") var isEnabled: Bool = true
    @AppStorage("screenshotAutoDeleteDays") var autoDeleteDays: Int = 7

    // MARK: Private State

    private var dispatchTimer: DispatchSourceTimer?

    private init() {}

    // MARK: - Computed Properties

    var screenshotsFolder: URL {
        if let vaultRoot = VaultLocationManager.shared.resolvedVaultRootURL {
            return vaultRoot.appendingPathComponent("Screenshots", isDirectory: true)
        }
        if let vaultParent = try? VaultRepository.documentVaultDirectoryURL() {
            return vaultParent.appendingPathComponent("Screenshots", isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("College/Screenshots", isDirectory: true)
    }

    private var desktopURL: URL {
        URL(fileURLWithPath: NSHomeDirectory() + "/Desktop", isDirectory: true)
    }

    // MARK: - Scanning

    /// Scans the Desktop for macOS screenshots older than `autoDeleteDays` days
    /// and appends them to `pendingScreenshots` (deduplicating).
    func scanDesktopForScreenshots() {
        guard isEnabled else { return }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: desktopURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -autoDeleteDays,
            to: Date()
        ) ?? Date()

        let pattern = try? NSRegularExpression(
            pattern: #"^(Screen Shot \d{4}-\d{2}-\d{2}|Screenshot \d{4}-)"#
        )

        var found: [URL] = []
        for url in contents {
            let filename = url.lastPathComponent
            let range = NSRange(filename.startIndex..., in: filename)
            guard pattern?.firstMatch(in: filename, range: range) != nil else { continue }

            if let attrs = try? url.resourceValues(forKeys: [.creationDateKey]),
               let created = attrs.creationDate,
               created <= cutoff {
                found.append(url)
            }
        }

        let existing = Set(pendingScreenshots.map { $0.standardizedFileURL })
        let newScreenshots = found.filter { !existing.contains($0.standardizedFileURL) }
        pendingScreenshots.append(contentsOf: newScreenshots)
    }

    // MARK: - Actions

    /// Moves `url` to ~/Documents/College/Screenshots/, creating the folder if needed.
    func moveToScreenshotsFolder(url: URL) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: screenshotsFolder, withIntermediateDirectories: true)
            let destination = screenshotsFolder.appendingPathComponent(url.lastPathComponent)
            let resolvedDest = fm.fileExists(atPath: destination.path)
                ? screenshotsFolder.appendingPathComponent(
                    "\(url.deletingPathExtension().lastPathComponent)-\(UUID().uuidString.prefix(6)).\(url.pathExtension)"
                  )
                : destination
            try fm.moveItem(at: url, to: resolvedDest)
            remove(url: url)
        } catch {
            AppNotificationCenter.shared.post(
                kind: .error,
                title: "Move Failed",
                message: error.localizedDescription
            )
        }
    }

    /// Deletes the screenshot from disk and removes it from `pendingScreenshots`.
    func deleteScreenshot(url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            AppNotificationCenter.shared.post(
                kind: .error,
                title: "Delete Failed",
                message: error.localizedDescription
            )
        }
        remove(url: url)
    }

    /// Removes `url` from `pendingScreenshots` without touching the file.
    func ignoreScreenshot(url: URL) {
        remove(url: url)
    }

    /// Imports the screenshot into the Vault under category `.other`.
    func importToVault(url: URL) async {
        do {
            try await CollegePersistence.shared.addVaultDocument(
                fromSelectedURL: url,
                category: .other,
                source: "screenshot"
            )
            remove(url: url)
            AppNotificationCenter.shared.post(
                kind: .success,
                title: "Screenshot Imported",
                message: "\(url.lastPathComponent) added to Vault.",
                isDismissible: true,
                autoDismissAfter: 5
            )
        } catch {
            AppNotificationCenter.shared.post(
                kind: .error,
                title: "Import Failed",
                message: error.localizedDescription
            )
        }
    }

    // MARK: - Scheduling

    /// Starts a repeating 24-hour timer that calls `scanDesktopForScreenshots()`.
    func scheduleDailyScan() {
        dispatchTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 24 * 60 * 60)
        timer.setEventHandler { [weak self] in
            self?.scanDesktopForScreenshots()
        }
        timer.resume()
        dispatchTimer = timer
        isDailyScanScheduled = true
    }

    func stopDailyScan() {
        dispatchTimer?.cancel()
        dispatchTimer = nil
        isDailyScanScheduled = false
    }

    // MARK: - Private Helpers

    private func remove(url: URL) {
        let std = url.standardizedFileURL
        pendingScreenshots.removeAll { $0.standardizedFileURL == std }
    }
}
