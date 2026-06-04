// CatalogStorePortableBridge.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogStorePortableBridge.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

@MainActor
enum CatalogStorePortableBridge {
    static func exportSignedCatalogStore(
        for universityName: String,
        appDataStore: AppDataStore = .shared
    ) throws -> URL {
        CatalogStoreSnapshotBridge.materializePerSchoolCatalogSnapshot(
            universityName: universityName,
            appDataStore: appDataStore
        )
        let schoolID = CatalogStoreCoordinator.shared.schoolID(for: universityName)
        let sqliteURL = CatalogStoreCoordinator.shared.localStoreStoreURL(for: schoolID)
        guard FileManager.default.fileExists(atPath: sqliteURL.path) else {
            throw NSError(
                domain: "CatalogStore",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "No local store catalog store on disk for \(universityName)."]
            )
        }
        let sqliteData = try Data(contentsOf: sqliteURL, options: [.mappedIfSafe])
        let signedData = try CatalogStoreSecurity.createSignedFile(schoolID: schoolID, sqliteData: sqliteData)

        let canonical = CatalogFileStore.catalogsDirectory
            .appendingPathComponent("\(universityName.replacingOccurrences(of: " ", with: "_"))_catalog.collegecatalog.sqlite")
        try signedData.write(to: canonical, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int16(0o444))], ofItemAtPath: canonical.path)

        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(universityName.replacingOccurrences(of: " ", with: "_"))_catalog_\(Int(Date().timeIntervalSince1970)).collegecatalog.sqlite")
        try signedData.write(to: temp, options: .atomic)
        return temp
    }

    static func importSignedCatalogStore(
        from url: URL,
        appDataStore: AppDataStore = .shared
    ) throws {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let verified = try CatalogStoreSecurity.verifySignedFile(data)
        let schoolID = verified.envelope.schoolID
        try CatalogStoreCoordinator.shared.ensureStoreDirectory(for: schoolID)
        let sqliteURL = CatalogStoreCoordinator.shared.localStoreStoreURL(for: schoolID)
        try verified.sqliteData.write(to: sqliteURL, options: .atomic)

        if let meta = try? inspectCatalogStoreMetadata(sqliteURL: sqliteURL) {
            CatalogStoreCoordinator.shared.upsertRegistryRecord(
                schoolID: schoolID,
                universityID: meta.id,
                universityName: meta.name
            )
            try appDataStore.setActiveCatalogSchoolID(schoolID)
            if let repo = appDataStore.catalogRepository {
                try repo.activateUniversity(id: meta.id, name: meta.name)
                try appDataStore.catalogSave()
            }
            AppDataStoreBridge.syncActiveCatalogSchool(universityName: meta.name)
            CatalogIngestPipeline.postCatalogDataDidCommit(
                universityID: meta.id,
                reason: "signed catalog sqlite import committed"
            )
        }
    }

    private static func inspectCatalogStoreMetadata(sqliteURL: URL) throws -> (id: UUID, name: String) {
        let configuration = ModelConfiguration(url: sqliteURL)
        let container = try ModelContainer(for: CollegeModelContainerFactory.catalogSchema, configurations: configuration)
        let context = container.mainContext
        var descriptor = FetchDescriptor<University>()
        descriptor.fetchLimit = 1
        guard let university = try context.fetch(descriptor).first,
              !university.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(
                domain: "CatalogStore",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "No university found in signed catalog store."]
            )
        }
        return (university.id, university.name)
    }
}
