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
        guard let (_, universityID) = CatalogStoreSnapshotBridge.attachUniversity(
            named: universityName,
            appDataStore: appDataStore,
            activate: true
        ) else {
            throw NSError(
                domain: "CatalogStore",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "No catalog data found for \(universityName)."]
            )
        }

        let schoolID = CatalogStoreCoordinator.shared.schoolID(for: universityName)
        let tempSQLite = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(schoolID)-catalog-export-\(Int(Date().timeIntervalSince1970)).sqlite")
        try CollegeUnifiedCatalogStoreMigration.materializeCatalogExtract(
            universityID: universityID,
            from: appDataStore.profileContext,
            to: tempSQLite
        )

        let sqliteData = try Data(contentsOf: tempSQLite, options: [.mappedIfSafe])
        defer { ModelStoreMaintenance.removeSQLiteBundle(at: tempSQLite) }
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

        let tempSQLite = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(schoolID)-catalog-import-\(Int(Date().timeIntervalSince1970)).sqlite")
        defer { ModelStoreMaintenance.removeSQLiteBundle(at: tempSQLite) }
        try verified.sqliteData.write(to: tempSQLite, options: .atomic)

        guard let universityID = CollegeUnifiedCatalogStoreMigration.importCatalogSQLite(
            at: tempSQLite,
            into: appDataStore.profileContext
        ) else {
            throw NSError(
                domain: "CatalogStore",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "No university found in signed catalog store."]
            )
        }

        if let meta = try? inspectCatalogStoreMetadata(sqliteURL: tempSQLite) {
            CatalogStoreCoordinator.shared.upsertRegistryRecord(
                schoolID: schoolID,
                universityID: meta.id,
                universityName: meta.name
            )
            try appDataStore.setActiveCatalogSchoolID(schoolID)
            if let repo = appDataStore.catalogRepository {
                try repo.activateUniversity(id: universityID, name: meta.name)
                try appDataStore.catalogSave()
            }
            AppDataStoreBridge.syncActiveCatalogSchool(universityName: meta.name)
            CatalogIngestPipeline.postCatalogDataDidCommit(
                universityID: meta.id,
                reason: "signed catalog sqlite import committed",
                commitPhase: .profile,
                programCount: 0,
                schoolID: schoolID
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
