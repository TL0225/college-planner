// CatalogSchoolRemoval.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogSchoolRemoval.
// Data: CollegePersistence / repositories when applicable.

import Foundation

@MainActor
enum CatalogSchoolRemoval {
    enum RemovalError: LocalizedError {
        case universityNotFound(String)

        var errorDescription: String? {
            switch self {
            case .universityNotFound(let schoolID):
                return "No catalog store found for school id \(schoolID)."
            }
        }
    }

    static func remove(schoolID: String) async throws {
        let records = CatalogStoreCoordinator.shared.loadRegistry()
        let record = records.first { $0.schoolID == schoolID }
        guard let record else { throw RemovalError.universityNotFound(schoolID) }

        try await CatalogVectorStore.shared.deleteAll(universityId: record.universityID)
        try await removeFileArtifacts(schoolID: schoolID, universityName: record.universityName)
        clearIngestMetadata(schoolID: schoolID)
        CatalogStoreCoordinator.shared.removeRegistryRecord(schoolID: schoolID)
    }

    static func clearIngestMetadata(schoolID: String) {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.contains(schoolID) {
            if key.hasPrefix("catalog.ingest.signature.v1.")
                || key.hasPrefix("catalog.ingest.checkpoint.")
                || key.hasPrefix("catalog.pdf.health.")
                || key.hasPrefix("catalog.integrity.")
                || key.hasPrefix("catalog.scrape.report.") {
                defaults.removeObject(forKey: key)
            }
        }
    }

    static func removeFileArtifacts(schoolID: String, universityName: String) async throws {
        let fm = FileManager.default
        let storeDir = CatalogStoreCoordinator.shared.storeDirectory(for: schoolID)
        try? fm.removeItem(at: storeDir)

        try? CatalogFileStore.delete(for: universityName)
        let signedSQLiteURL = CatalogFileStore.catalogsDirectory
            .appendingPathComponent("\(universityName.replacingOccurrences(of: " ", with: "_"))_catalog.collegecatalog.sqlite")
        try? fm.removeItem(at: signedSQLiteURL)
        try? fm.removeItem(at: CatalogArchiveStore.cachedPDFURL(schoolID: schoolID))
        let archiveIndexURL = CatalogArchiveStore.cachedPDFURL(schoolID: schoolID)
            .deletingPathExtension()
            .appendingPathExtension("json")
        try? fm.removeItem(at: archiveIndexURL)
    }
}
