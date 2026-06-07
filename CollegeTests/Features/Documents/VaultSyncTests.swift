// VaultSyncTests.swift
// Feature: Documents
// Purpose: Documents module — VaultSyncTests.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import XCTest
@testable import College

@MainActor
final class VaultSyncTests: PersistenceTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        let ctx = AppDataStore.shared.profileContext
        for doc in try ctx.fetch(FetchDescriptor<VaultDocument>()) {
            ctx.delete(doc)
        }
        for folder in try ctx.fetch(FetchDescriptor<WatchedFolder>()) {
            ctx.delete(folder)
        }
        try ctx.save()
    }

    func testVaultRepositoryPersistsDocumentMetadata() throws {
        let documentID = UUID()
        let doc = VaultDocument(
            id: documentID,
            fileName: "Syllabus.pdf",
            category: CollegePersistence.VaultDocumentCategory.syllabi.rawValue,
            addedAt: .now,
            fileSizeBytes: 1024,
            localRelativePath: "test-syllabus.colenc",
            isFavorite: true,
            sortOrder: 1,
            isFolder: false
        )
        profileContext.insert(doc)
        try profileContext.save()

        let vaultRepo = VaultRepository(context: profileContext)
        let mirrored = try vaultRepo.fetchDocument(id: documentID)
        XCTAssertNotNil(mirrored)
        XCTAssertEqual(mirrored?.fileName, "Syllabus.pdf")
        XCTAssertEqual(mirrored?.category, CollegePersistence.VaultDocumentCategory.syllabi.rawValue)
        XCTAssertEqual(mirrored?.fileSizeBytes, 1024)
        XCTAssertTrue(mirrored?.isFavorite == true)
        XCTAssertTrue(try vaultRepo.hasMirroredVaultDocumentRows())
    }

    func testDeleteVaultDocumentRemovesRow() throws {
        let doc = VaultDocument(
            fileName: "Temporary.pdf",
            category: CollegePersistence.VaultDocumentCategory.other.rawValue,
            addedAt: .now,
            localRelativePath: "temp.colenc",
            isFolder: false
        )
        profileContext.insert(doc)
        try profileContext.save()

        let vaultRepo = VaultRepository(context: profileContext)
        XCTAssertEqual(try vaultRepo.fetchDocumentCount(), 1)
        try vaultRepo.deleteVaultDocument(id: doc.id)
        try profileContext.save()
        XCTAssertEqual(try vaultRepo.fetchDocumentCount(), 0)
    }

    func testFavoriteTogglePersists() throws {
        let documentID = UUID()
        let doc = VaultDocument(
            id: documentID,
            fileName: "Resume.pdf",
            category: CollegePersistence.VaultDocumentCategory.careerResume.rawValue,
            addedAt: .now,
            localRelativePath: "resume.colenc",
            isFavorite: false,
            isFolder: false
        )
        profileContext.insert(doc)
        try profileContext.save()

        let vaultRepo = VaultRepository(context: profileContext)
        XCTAssertEqual(try vaultRepo.fetchDocument(id: documentID)?.isFavorite, false)
        doc.isFavorite = true
        try profileContext.save()
        XCTAssertEqual(try vaultRepo.fetchDocument(id: documentID)?.isFavorite, true)
    }

    func testExtendedMetadataRoundTrip() throws {
        let documentID = UUID()
        let doc = VaultDocument(
            id: documentID,
            fileName: "Syllabus.pdf",
            category: CollegePersistence.VaultDocumentCategory.syllabi.rawValue,
            addedAt: .now,
            localRelativePath: "test-syllabus.colenc",
            isFolder: false
        )
        doc.customDisplayName = "CSE 191 Syllabus"
        doc.courseCodeLinked = "CSE 191"
        doc.lastOpenedAt = Date().addingTimeInterval(-3600)
        profileContext.insert(doc)
        try profileContext.save()

        let mirrored = try VaultRepository(context: profileContext).fetchDocument(id: documentID)
        XCTAssertEqual(mirrored?.customDisplayName, "CSE 191 Syllabus")
        XCTAssertEqual(mirrored?.courseCodeLinked, "CSE 191")
        XCTAssertNotNil(mirrored?.lastOpenedAt)
    }

    func testWatchedFolderPersists() throws {
        let folder = WatchedFolder(path: "/Users/test/Downloads", isEnabled: true, addedAt: .now)
        profileContext.insert(folder)
        try profileContext.save()

        let folders = try VaultRepository(context: profileContext).fetchWatchedFolders(limit: 5)
        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(folders.first?.path, "/Users/test/Downloads")
        XCTAssertTrue(folders.first?.isEnabled == true)
    }
}
