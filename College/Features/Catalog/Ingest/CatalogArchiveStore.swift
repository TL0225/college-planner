// CatalogArchiveStore.swift
// Feature: Catalog
// Purpose: Catalog module — Section.
// Data: CollegePersistence / repositories when applicable.

import CryptoKit
import Foundation

/// File-backed Pass B archive index (page/section text not surfaced in academic UI).
enum CatalogArchiveStore {
    struct Section: Codable, Sendable, Identifiable {
        var id: String { sectionKey }
        let sectionKey: String
        let title: String
        let classifiedType: String
        let startPage: Int?
        let endPage: Int?
        let sourceURL: String?
        let contentHash: String
        let bodyPreview: String
    }

    struct Index: Codable, Sendable {
        let schoolID: String
        let sourceFormat: String
        let totalPages: Int
        let archivedPages: Int
        let parserVersion: String
        let pdfSHA256: String?
        let updatedAt: Date
        let sections: [Section]
    }

    private static let parserVersion = "1.0.0-archive-v1"

    private static var archiveRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("College", isDirectory: true)
            .appendingPathComponent("CatalogArchive", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static func indexURL(schoolID: String) -> URL {
        archiveRoot.appendingPathComponent("\(schoolID).json")
    }

    static func cachedPDFURL(schoolID: String) -> URL {
        archiveRoot.appendingPathComponent("\(schoolID).pdf")
    }

    @discardableResult
    static func writeCachedPDF(data: Data, schoolID: String) throws -> URL {
        let url = cachedPDFURL(schoolID: schoolID)
        try data.write(to: url, options: .atomic)
        return url
    }

    @discardableResult
    static func writeCachedPDF(from sourceURL: URL, schoolID: String) throws -> URL {
        let destination = cachedPDFURL(schoolID: schoolID)
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: sourceURL, to: destination)
        return destination
    }

    static func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            guard let chunk = try handle.read(upToCount: 131_072), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func loadIndex(schoolID: String) -> Index? {
        let url = indexURL(schoolID: schoolID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Index.self, from: data)
    }

    static func saveIndex(_ index: Index) throws {
        let url = indexURL(schoolID: index.schoolID)
        let data = try JSONEncoder().encode(index)
        try data.write(to: url, options: .atomic)
    }

    static func isArchiveReady(schoolID: String) -> Bool {
        guard let index = loadIndex(schoolID: schoolID) else { return false }
        guard index.totalPages > 0 else { return false }
        return index.archivedPages >= index.totalPages
    }

    static func contentHash(for text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Archives every PDF page as a lightweight section row (Pass B).
    static func archivePDFPages(
        schoolID: String,
        pdfURL: URL,
        pdfSHA256: String?,
        onProgress: ((Int, Int) -> Void)? = nil
    ) async throws {
        let engine = PDFCatalogEngine()
        let foundation = try await engine.buildFoundation(from: pdfURL)
        let extractor = try PDFTextExtractor(pdfURL: pdfURL)
        let total = foundation.pageCount
        var sections: [Section] = []
        sections.reserveCapacity(total)

        let batchSize = 50
        for start in stride(from: 0, to: total, by: batchSize) {
            let end = min(start + batchSize, total)
            let range = start..<end
            let (pagesText, _) = await extractor.extractPagesText(pageRange: range, ocrFallback: true)
            for pageIndex in range {
                let text = (pagesText[pageIndex] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let preview = String(text.prefix(400))
                let hash = contentHash(for: text)
                sections.append(
                    Section(
                        sectionKey: "page:\(pageIndex)",
                        title: "Page \(pageIndex + 1)",
                        classifiedType: "archive_page",
                        startPage: pageIndex,
                        endPage: pageIndex,
                        sourceURL: pdfURL.absoluteString,
                        contentHash: hash,
                        bodyPreview: preview
                    )
                )
            }
            onProgress?(end, total)
            await Task.yield()
        }

        let index = Index(
            schoolID: schoolID,
            sourceFormat: "pdf",
            totalPages: total,
            archivedPages: sections.count,
            parserVersion: parserVersion,
            pdfSHA256: pdfSHA256,
            updatedAt: Date(),
            sections: sections
        )
        try saveIndex(index)
    }
}
