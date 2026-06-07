// AppBackupRestoreStoreTests.swift
// Feature: Shared
// Purpose: Shared module — AppBackupRestoreStoreTests.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import XCTest
@testable import College

@MainActor
final class AppBackupRestoreStoreTests: XCTestCase {
    private let activeSchoolKey = "catalog.activeSchoolID"

    func testExportImport_roundTripsProfileAndCatalogStores() throws {
        let suffix = UUID().uuidString.prefix(8)
        let schoolA = "backup_a_\(suffix)"
        let schoolB = "backup_b_\(suffix)"
        let backupURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-\(UUID().uuidString).colbk")

        SecurityManager.shared.installMasterKeyForUnitTestingIfNeeded()
        ModelStoreMaintenance.removeAllOnDiskStores()
        clearCatalogRegistry()

        defer {
            try? FileManager.default.removeItem(at: backupURL)
            ModelStoreMaintenance.removeAllOnDiskStores()
            clearCatalogRegistry()
        }

        try seedOnDiskProfile(name: "Backup Student")
        try seedOnDiskCatalog(schoolID: schoolA, universityName: "Backup U A")
        try seedOnDiskCatalog(schoolID: schoolB, universityName: "Backup U B")
        CatalogStoreCoordinator.shared.upsertRegistryRecord(
            schoolID: schoolA,
            universityID: UUID(),
            universityName: "Backup U A"
        )
        CatalogStoreCoordinator.shared.upsertRegistryRecord(
            schoolID: schoolB,
            universityID: UUID(),
            universityName: "Backup U B"
        )
        UserDefaults.standard.set(schoolA, forKey: activeSchoolKey)

        try AppBackupManager.exportBackup(to: backupURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))

        ModelStoreMaintenance.removeAllOnDiskStores()
        clearCatalogRegistry()
        UserDefaults.standard.removeObject(forKey: activeSchoolKey)

        try AppBackupManager.importBackup(from: backupURL)

        XCTAssertEqual(UserDefaults.standard.string(forKey: activeSchoolKey), schoolA)
        XCTAssertEqual(try fetchProfileNames().sorted(), ["Backup Student"])
        XCTAssertEqual(
            try fetchUniversityNames(for: [schoolA, schoolB]).sorted(),
            ["Backup U A", "Backup U B"]
        )
    }

    private func seedOnDiskProfile(name: String) throws {
        let container = try CollegeModelContainerFactory.makeProfileContainer()
        let context = container.mainContext
        context.insert(Profile(name: name))
        try context.save()
    }

    private func seedOnDiskCatalog(schoolID: String, universityName: String) throws {
        let container = try CollegeModelContainerFactory.makeCatalogContainer(schoolID: schoolID)
        let context = container.mainContext
        context.insert(University(name: universityName, isActive: false))
        try context.save()
    }

    private func fetchProfileNames() throws -> [String] {
        let container = try CollegeModelContainerFactory.makeProfileContainer()
        return try container.mainContext.fetch(FetchDescriptor<Profile>()).compactMap(\.name)
    }

    private func fetchUniversityNames(for schoolIDs: [String]) throws -> [String] {
        var names: [String] = []
        for schoolID in schoolIDs {
            let url = CollegeModelContainerFactory.catalogStoreURL(for: schoolID)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            let configuration = ModelConfiguration(url: url)
            let container = try ModelContainer(
                for: CollegeModelContainerFactory.catalogSchema,
                configurations: configuration
            )
            let universities = try container.mainContext.fetch(FetchDescriptor<University>())
            names.append(contentsOf: universities.compactMap(\.name))
        }
        return names
    }

    private func clearCatalogRegistry() {
        for schoolID in CatalogStoreCoordinator.shared.loadRegistry().map(\.schoolID) {
            CatalogStoreCoordinator.shared.removeRegistryRecord(schoolID: schoolID)
        }
    }
}
