// CatalogFileStore.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogFileStore.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CatalogFileStore {
    private static let catalogsSubpath = "College/catalogs"

    static var catalogsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent(catalogsSubpath, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func fileURL(for schoolName: String) -> URL {
        catalogsDirectory.appendingPathComponent(CatalogBundleNaming.canonicalFilename(for: schoolName))
    }

    static func save(envelope: CatalogBundleEnvelope, for schoolName: String) throws {
        let url = fileURL(for: schoolName)
        let data = try CatalogBundleSecurity.encodeEnvelope(envelope)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o444))],
            ofItemAtPath: url.path
        )
    }

    static func load(for schoolName: String) throws -> CatalogBundleEnvelope? {
        let url = fileURL(for: schoolName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CatalogBundleEnvelope.self, from: data)
    }

    static func shareableCopy(for schoolName: String) throws -> URL {
        guard let envelope = try load(for: schoolName) else {
            throw CatalogFileStoreError.noCanonicalFile(schoolName)
        }
        let tempDir = FileManager.default.temporaryDirectory
        let filename = CatalogBundleNaming.shareableFilename(for: schoolName)
        let dest = tempDir.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        let data = try CatalogBundleSecurity.encodeEnvelope(envelope)
        try data.write(to: dest, options: .atomic)
        return dest
    }

    static func listLocalCatalogs() -> [LocalCatalogInfo] {
        let dir = catalogsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return files
            .filter { $0.pathExtension.lowercased() == CatalogBundle.fileExtension }
            .compactMap { url -> LocalCatalogInfo? in
                let name = schoolName(fromCanonicalURL: url) ?? url.deletingPathExtension().lastPathComponent
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let fingerprint: String? = {
                    guard let data = try? Data(contentsOf: url),
                          let envelope = try? JSONDecoder().decode(CatalogBundleEnvelope.self, from: data) else {
                        return nil
                    }
                    return envelope.signerFingerprint
                }()
                return LocalCatalogInfo(
                    schoolName: name,
                    fileURL: url,
                    fileSize: Int64(values?.fileSize ?? 0),
                    lastModified: values?.contentModificationDate ?? Date.distantPast,
                    signerFingerprint: fingerprint
                )
            }
            .sorted { $0.schoolName.localizedCaseInsensitiveCompare($1.schoolName) == .orderedAscending }
    }

    static func delete(for schoolName: String) throws {
        let url = fileURL(for: schoolName)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private static func schoolName(fromCanonicalURL url: URL) -> String? {
        let base = url.deletingPathExtension().lastPathComponent
        let suffix = "_catalog"
        guard base.hasSuffix(suffix) else { return nil }
        return String(base.dropLast(suffix.count)).replacingOccurrences(of: "_", with: " ")
    }

    enum CatalogFileStoreError: LocalizedError {
        case noCanonicalFile(String)

        var errorDescription: String? {
            switch self {
            case .noCanonicalFile(let school):
                return "No saved catalog bundle for \(school). Export or scrape the catalog first."
            }
        }
    }
}
