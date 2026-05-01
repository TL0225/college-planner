import Foundation
import WebKit

// MARK: - BrightspaceDownloadManager
// WKDownloadDelegate that routes completed downloads to the Vault.

@MainActor
final class BrightspaceDownloadManager: NSObject, WKDownloadDelegate {

    var onDownloadAdded: ((BrightspaceDownload) -> Void)?
    var onDownloadProgress: ((UUID, Double) -> Void)?
    /// Network bytes finished; vault import is about to start (UI: importing phase).
    var onVaultImportStarted: ((UUID) -> Void)?
    /// Remove the download row (after vault import or unrecoverable failure).
    var onDownloadRowDismiss: ((UUID) -> Void)?

    private let downloadId = UUID()
    private var destinationURL: URL?
    private var suggestedFilename: String = "download"

    // MARK: - WKDownloadDelegate

    func download(_ download: WKDownload,
                  decideDestinationUsing response: URLResponse,
                  suggestedFilename: String) async -> URL? {
        let filename = suggestedFilename.isEmpty ? "download" : suggestedFilename
        let dlId = downloadId
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrightspaceDownloads", isDirectory: true)
            .appendingPathComponent(dlId.uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            await MainActor.run {
                _ = AppNotificationCenter.shared.post(
                    kind: .error,
                    title: String(localized: "brightspace.download.failed_title"),
                    message: String(format: String(localized: "brightspace.download.temp_dir_failed_format"), filename)
                )
            }
            return nil
        }
        let dest = tempDir.appendingPathComponent(filename)
        self.suggestedFilename = filename
        self.destinationURL = dest
        let dl = BrightspaceDownload(id: dlId, filename: filename, progress: 0, state: .downloading)
        onDownloadAdded?(dl)
        return dest
    }

    func download(_ download: WKDownload,
                  didReceive challenge: URLAuthenticationChallenge) async
    -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        (.performDefaultHandling, nil)
    }

    /// LMS file links often 302 through auth or CDN hosts; without this, WebKit can cancel the download.
    func download(
        _ download: WKDownload,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        decisionHandler: @escaping @MainActor @Sendable (WKDownload.RedirectPolicy) -> Void
    ) {
        decisionHandler(.allow)
    }

    func download(_ download: WKDownload,
                  didWriteData bytesWritten: Int64,
                  totalBytesWritten: Int64,
                  totalBytesExpectedToWrite: Int64) {
        let progress = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        onDownloadProgress?(downloadId, progress)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let src = destinationURL else {
            Task { @MainActor in
                AppNotificationCenter.shared.post(
                    kind: .error,
                    title: String(localized: "brightspace.download.failed_title"),
                    message: String(format: String(localized: "brightspace.download.missing_file_format"), suggestedFilename)
                )
                onDownloadRowDismiss?(downloadId)
            }
            return
        }
        onVaultImportStarted?(downloadId)
        Task { @MainActor in
            defer { self.onDownloadRowDismiss?(self.downloadId) }
            do {
                try await self.importIntoVault(from: src)
            } catch {
                let detail = Self.userFacingErrorDetail(error)
                let filename = suggestedFilename
                await MainActor.run {
                    _ = AppNotificationCenter.shared.post(
                        kind: .error,
                        title: String(localized: "brightspace.download.vault_failed_title"),
                        message: String(format: String(localized: "brightspace.download.vault_failed_format"),
                                        filename, detail)
                    )
                }
            }
            try? FileManager.default.removeItem(at: src.deletingLastPathComponent())
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        if let dest = destinationURL {
            try? FileManager.default.removeItem(at: dest)
            let uuidFolder = dest.deletingLastPathComponent()
            try? FileManager.default.removeItem(at: uuidFolder)
        }
        let filename = suggestedFilename
        let detail = Self.userFacingErrorDetail(error)
        Task { @MainActor in
            onDownloadRowDismiss?(downloadId)
            AppNotificationCenter.shared.post(
                kind: .error,
                title: String(localized: "brightspace.download.failed_title"),
                message: String(format: String(localized: "brightspace.download.network_failed_format"),
                                filename, detail)
            )
        }
    }

    /// Prefer nested Core Data validation messages over the generic "Multiple validation errors occurred."
    private static func userFacingErrorDetail(_ error: Error) -> String {
        let ns = error as NSError
        if let detailed = ns.userInfo[NSDetailedErrorsKey] as? [NSError] {
            let parts = detailed.map(\.localizedDescription).filter { !$0.isEmpty }
            if !parts.isEmpty {
                return parts.joined(separator: " ")
            }
        }
        return ns.localizedDescription
    }

    // MARK: - Vault integration

    private func importIntoVault(from url: URL) async throws {
        let filename = url.lastPathComponent
        Self.copyToUserDownloadsFolder(from: url, suggestedFilename: filename)
        let category = Self.inferCategory(filename: filename)
        try await VaultImportSerialQueue.shared.run {
            try await Task { @MainActor in
                try await CoreDataManager.shared.addVaultDocument(
                    fromSelectedURL: url,
                    category: category,
                    source: "brightspace"
                )
            }.value
        }
        await MainActor.run {
            _ = AppNotificationCenter.shared.post(
                kind: .success,
                title: String(localized: "brightspace.download.saved_title"),
                message: String(format: String(localized: "brightspace.download.saved_message_format"), filename)
            )
        }
    }

    /// Best-effort copy for Finder visibility; vault remains the canonical encrypted store.
    private static func copyToUserDownloadsFolder(from fileURL: URL, suggestedFilename: String) {
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
        let baseName = (suggestedFilename as NSString).lastPathComponent
        var dest = downloads.appendingPathComponent(baseName)
        var n = 1
        let ext = dest.pathExtension
        let stem = dest.deletingPathExtension().lastPathComponent
        while FileManager.default.fileExists(atPath: dest.path) {
            let name = ext.isEmpty ? "\(stem) (\(n))" : "\(stem) (\(n)).\(ext)"
            dest = downloads.appendingPathComponent(name)
            n += 1
        }
        try? FileManager.default.copyItem(at: fileURL, to: dest)
    }

    // MARK: - Smart category inference

    static func inferCategory(filename: String) -> CoreDataManager.VaultDocumentCategory {
        let lower = filename.lowercased()
        if lower.contains("syllabus") || lower.contains("syllabi") ||
           lower.contains("course outline") || lower.contains("course_outline") ||
           lower.contains("course-outline") || lower.contains("courseinfo") ||
           lower.contains("course info") {
            return .syllabi
        }
        if lower.contains("transcript") || lower.contains("academic record") ||
           lower.contains("unofficial") || lower.contains("degree audit") {
            return .transcripts
        }
        if lower.contains("calendar") || lower.contains("schedule") ||
           lower.contains("timetable") || lower.hasSuffix(".ics") {
            return .calendar
        }
        return .other
    }

    // MARK: - Temp directory hygiene

    /// Removes per-download UUID folders under `BrightspaceDownloads` that were left behind (failed/cancelled)
    /// or are older than `maxAge` (default 24h). Safe to call from Brightspace tab `onAppear`.
    static func sweepStaleBrightspaceDownloadFolders(maxAge: TimeInterval = 86_400) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BrightspaceDownloads", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        let cutoff = Date().addingTimeInterval(-maxAge)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for dir in urls {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let mod = (try? dir.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if mod < cutoff {
                try? FileManager.default.removeItem(at: dir)
            }
        }
    }
}
