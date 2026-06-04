// CatalogBackgroundSyncStoreTests.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogBackgroundSyncStoreTests.
// Data: CollegePersistence / repositories when applicable.

import CryptoKit
import XCTest
@testable import College

final class CatalogBackgroundSyncStoreTests: XCTestCase {
    @MainActor
    func testWriteCachedPDF_fromFileURL_roundTripsBytes() throws {
        let schoolID = "sync_pdf_\(UUID().uuidString.prefix(8))"
        let fm = FileManager.default
        let source = fm.temporaryDirectory.appendingPathComponent("source-\(UUID().uuidString).pdf")
        let payload = Data("%PDF-1.4 catalog-sync-test".utf8)
        try payload.write(to: source, options: .atomic)
        defer { try? fm.removeItem(at: source) }

        let cachedURL = try CatalogArchiveStore.writeCachedPDF(from: source, schoolID: schoolID)
        defer { try? fm.removeItem(at: cachedURL) }

        XCTAssertTrue(fm.fileExists(atPath: cachedURL.path))
        XCTAssertEqual(try Data(contentsOf: cachedURL), payload)
        XCTAssertEqual(
            try CatalogArchiveStore.sha256Hex(of: cachedURL),
            SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        )
    }

    @MainActor
    func testDownloadToTemporaryFileWithProgress_writesLocalFileWithoutNetwork() async throws {
        let fm = FileManager.default
        let source = fm.temporaryDirectory.appendingPathComponent("local-download-\(UUID().uuidString).bin")
        let payload = Data(repeating: 0xAB, count: 300_000)
        try payload.write(to: source, options: .atomic)
        defer { try? fm.removeItem(at: source) }

        var progressUpdates: [(Int, Int)] = []
        let partURL = try await CatalogBackgroundSyncRunner.downloadToTemporaryFileWithProgress(
            from: source,
            onProgress: { completed, total in
                progressUpdates.append((completed, total))
            }
        )
        defer { try? fm.removeItem(at: partURL) }

        XCTAssertEqual(try Data(contentsOf: partURL), payload)
        XCTAssertFalse(progressUpdates.isEmpty)
        XCTAssertEqual(progressUpdates.last?.0, payload.count)
    }
}
