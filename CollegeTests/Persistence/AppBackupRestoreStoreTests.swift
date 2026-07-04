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

    func testExportImport_roundTripsProfileAndCatalogStores() async throws {
        let suffix = UUID().uuidString.prefix(8)
        let schoolA = "backup_a_\(suffix)"
        let backupURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-\(UUID().uuidString).colbk")

        SecurityManager.shared.installMasterKeyForUnitTestingIfNeeded()
        try AppDataStore.shared.clearProfileStoreForUnitTesting()
        ModelStoreMaintenance.removeAllOnDiskStores()

        defer {
            try? FileManager.default.removeItem(at: backupURL)
            ModelStoreMaintenance.removeAllOnDiskStores()
        }

        try seedOnDiskProfile(
            name: "Backup Student",
            universities: ["Backup U A", "Backup U B"]
        )
        UserDefaults.standard.set(schoolA, forKey: activeSchoolKey)

        try await AppBackupManager.exportBackup(to: backupURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))

        ModelStoreMaintenance.removeAllOnDiskStores()
        UserDefaults.standard.removeObject(forKey: activeSchoolKey)

        try await AppBackupManager.importBackup(from: backupURL)
        try ModelStoreMaintenance.finalizeProfileStoreForBackup()

        XCTAssertEqual(UserDefaults.standard.string(forKey: activeSchoolKey), schoolA)
        XCTAssertEqual(try fetchProfileNames().sorted(), ["Backup Student"])
        XCTAssertEqual(
            try fetchUniversityNamesFromProfile().sorted(),
            ["Backup U A", "Backup U B"]
        )
    }

    private func seedOnDiskProfile(name: String, universities: [String] = []) throws {
        let container = try CollegeModelContainerFactory.makeProfileContainer()
        let context = container.mainContext
        context.insert(Profile(name: name))
        for universityName in universities {
            context.insert(University(name: universityName, isActive: false))
        }
        try context.save()
        try ModelStoreMaintenance.finalizeProfileStoreForBackup()
    }

    private func fetchProfileNames() throws -> [String] {
        let container = try CollegeModelContainerFactory.makeProfileContainer()
        return try container.mainContext.fetch(FetchDescriptor<Profile>()).compactMap(\.name)
    }

    private func fetchUniversityNamesFromProfile() throws -> [String] {
        let container = try CollegeModelContainerFactory.makeProfileContainer()
        return try container.mainContext.fetch(FetchDescriptor<University>()).compactMap(\.name)
    }
}
