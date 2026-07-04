// StaleFileMonitor.swift
// Feature: Core
// Purpose: Core module — StaleFileMonitor.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftUI
import Combine

// MARK: - StaleFileMonitor

/// Periodically scans folders watched by ``FSWatchdogService`` for academic
/// files that haven't been organised into the vault yet, and surfaces an
/// in-app notification when stale files are discovered.
@MainActor final class StaleFileMonitor: ObservableObject {

    // MARK: Singleton

    static let shared = StaleFileMonitor()
    private init() {}

    // MARK: - Published State

    @Published var staleFilesDetected: Int = 0
    @Published private(set) var isMonitoring: Bool = false

    // MARK: - App Storage

    @AppStorage("staleFileThresholdDays") var thresholdDays: Int = 7

    // MARK: - Private State

    private var timer: DispatchSourceTimer?

    // MARK: - Timer Interval

    private let scanInterval: TimeInterval = 30 * 60 // 30 minutes

    // MARK: - Vault Root

    private var vaultRootPath: String {
        if let configured = try? VaultRepository.documentVaultDirectoryURL() {
            return configured.deletingLastPathComponent().path
        }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return appSupport?
            .appendingPathComponent("College", isDirectory: true)
            .path
            ?? FileManager.default.homeDirectoryForCurrentUser.path
    }

    // MARK: - Monitoring Lifecycle

    /// Sets up a DispatchSourceTimer that fires every 30 minutes and activates it.
    func startMonitoring() {
        stopMonitoring()

        let source = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        source.schedule(
            deadline: .now() + scanInterval,
            repeating: scanInterval,
            leeway: .seconds(30)
        )
        // Use @Sendable to prevent Swift 6 from inferring @MainActor isolation on this
        // closure. Without it, Swift 6 checks that the closure executes on the main actor
        // when the timer fires on the utility-qos queue → dispatch_assert_queue crash.
        source.setEventHandler { @Sendable [weak self] in
            Task { @MainActor [weak self] in
                await self?.scanNow()
            }
        }
        source.activate()
        timer = source
        isMonitoring = true
    }

    /// Cancels the background timer.
    func stopMonitoring() {
        timer?.cancel()
        timer = nil
        isMonitoring = false
    }

    // MARK: - Scan

    /// Scans all paths watched by ``FSWatchdogService`` for unorganised academic
    /// files older than `thresholdDays` days and posts an in-app notification if
    /// any are found.
    func scanNow() async {
        let watchedPaths = FSWatchdogService.shared.watchedPaths
        guard !watchedPaths.isEmpty else { return }

        let thresholdDays = thresholdDays
        let vaultRootPath = vaultRootPath
        let staleCount = await Task.detached(priority: .utility) {
            Self.countStaleFiles(
                watchedPaths: watchedPaths,
                thresholdDays: thresholdDays,
                vaultRootPath: vaultRootPath
            )
        }.value

        staleFilesDetected = staleCount

        guard staleCount > 0 else { return }

        _ = AppNotificationCenter.shared.post(
            kind: .info,
            title: "Organize Your Files",
            message: "\(staleCount) academic file\(staleCount == 1 ? "" : "s") haven't been organized yet. Tap to review.",
            isDismissible: true,
            autoDismissAfter: 12
        )
    }

    // MARK: - Helpers

    /// Returns `true` when the file's name or extension suggests it is an
    /// academic document (homework, syllabus, notes, etc.).
    private nonisolated static func isAcademicFile(url: URL) -> Bool {
        let academicExtensions: Set<String> = ["pdf", "docx", "doc"]
        let academicKeywords: [String] = [
            "hw", "homework", "assignment", "exam", "midterm", "final",
            "notes", "syllabus", "lab", "project", "lecture", "reading", "quiz"
        ]

        // Check by extension
        if academicExtensions.contains(url.pathExtension.lowercased()) {
            return true
        }

        // Check filename for academic keywords
        let lowercasedName = url.deletingPathExtension().lastPathComponent.lowercased()
        return academicKeywords.contains { keyword in
            lowercasedName.contains(keyword)
        }
    }

    /// Returns the number of days since the file at `url` was last modified.
    /// Returns `Int.max` on failure so the file is treated as stale.
    private nonisolated static func daysSinceModification(url: URL) -> Int {
        guard
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
            let modDate = attrs[.modificationDate] as? Date
        else { return Int.max }

        let days = Calendar.current.dateComponents([.day], from: modDate, to: Date()).day ?? 0
        return max(days, 0)
    }

    // MARK: - Private Helpers

    /// Returns `true` when `url` already lives inside the vault root directory.
    private nonisolated static func isInVault(url: URL, vaultRootPath: String) -> Bool {
        url.path.hasPrefix(vaultRootPath)
    }

    private nonisolated static func countStaleFiles(
        watchedPaths: [String],
        thresholdDays: Int,
        vaultRootPath: String
    ) -> Int {
        var staleCount = 0

        for folder in watchedPaths {
            let folderURL = URL(fileURLWithPath: folder)
            guard let enumerator = FileManager.default.enumerator(
                at: folderURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                guard isAcademicFile(url: url) else { continue }
                guard !isInVault(url: url, vaultRootPath: vaultRootPath) else { continue }
                guard daysSinceModification(url: url) >= thresholdDays else { continue }
                staleCount += 1
            }
        }

        return staleCount
    }
}
