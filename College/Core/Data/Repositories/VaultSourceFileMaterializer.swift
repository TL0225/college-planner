// VaultSourceFileMaterializer.swift
// Feature: Core/Data
// Purpose: Materialize user-selected files from local disk, iCloud, or third-party cloud folders.

import Foundation

enum VaultSourceFileMaterializer {
    enum MaterializeError: LocalizedError {
        case emptyFile
        case cloudDownloadTimedOut

        var errorDescription: String? {
            switch self {
            case .emptyFile:
                "The selected file is empty or could not be read."
            case .cloudDownloadTimedOut:
                "This file is still downloading from cloud storage. Open it in Finder until the download finishes, then try again."
            }
        }
    }

    /// Reads bytes from a user-selected file, waiting for cloud placeholders when needed.
    static func materializedDataAsync(from url: URL, downloadTimeout: TimeInterval = 45) async throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        try kickOffRemoteDownloadIfNeeded(at: url)

        let deadline = Date().addingTimeInterval(downloadTimeout)
        var lastError: Error = MaterializeError.emptyFile

        while Date() < deadline {
            try kickOffRemoteDownloadIfNeeded(at: url)

            do {
                let data = try readWithFileCoordinator(at: url)
                if !data.isEmpty { return data }
                lastError = MaterializeError.emptyFile
            } catch {
                lastError = error
            }

            guard shouldRetryRemoteRead(at: url) else { break }
            try await Task.sleep(nanoseconds: 250_000_000)
        }

        if shouldRetryRemoteRead(at: url) {
            throw MaterializeError.cloudDownloadTimedOut
        }
        throw lastError
    }

    /// Copies a user-selected file into a local temp URL with its original filename/extension.
    static func materializedTempURL(
        from url: URL,
        preferredFileName: String? = nil,
        downloadTimeout: TimeInterval = 45
    ) async throws -> URL {
        let data = try await materializedDataAsync(from: url, downloadTimeout: downloadTimeout)
        let name = preferredFileName ?? url.lastPathComponent
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("College-Materialized-\(UUID().uuidString)-\(name)")
        try data.write(to: tempURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tempURL.path)
        return tempURL
    }

    private static func kickOffRemoteDownloadIfNeeded(at url: URL) throws {
        let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey,
        ])

        if values?.isUbiquitousItem == true,
           let status = values?.ubiquitousItemDownloadingStatus,
           status != .current {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
    }

    private static func shouldRetryRemoteRead(at url: URL) -> Bool {
        if isLikelyCloudHosted(url) { return true }

        let values = try? url.resourceValues(forKeys: [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
        ])

        if values?.isUbiquitousItem == true {
            if values?.ubiquitousItemIsDownloading == true { return true }
            if let status = values?.ubiquitousItemDownloadingStatus, status != .current {
                return true
            }
        }

        let fileSize = values?.fileSize ?? 0
        let allocated = values?.totalFileAllocatedSize ?? 0
        if fileSize == 0 && allocated == 0 && isLikelyCloudHosted(url) {
            return true
        }

        return false
    }

    private static func isLikelyCloudHosted(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        if path.contains("/library/mobile documents/")
            || path.contains("/library/clouddocs/")
            || path.contains("/library/cloudstorage/") {
            return true
        }
        if (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true {
            return true
        }
        return false
    }

    private static func readWithFileCoordinator(at url: URL) throws -> Data {
        var coordinatorError: NSError?
        var payload: Data?
        var readError: Error?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinatorError) { readURL in
            do {
                payload = try Data(contentsOf: readURL)
            } catch {
                readError = error
            }
        }

        if let coordinatorError { throw coordinatorError }
        if let readError { throw readError }
        return payload ?? Data()
    }
}
