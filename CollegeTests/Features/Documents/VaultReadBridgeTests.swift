// VaultReadBridgeTests.swift
// Feature: Documents
// Purpose: Documents module — VaultReadBridgeTests.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import XCTest
@testable import College

@MainActor
final class VaultReadBridgeTests: PersistenceTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        let ctx = AppDataStore.shared.profileContext
        for doc in try ctx.fetch(FetchDescriptor<VaultDocument>()) {
            ctx.delete(doc)
        }
        try ctx.save()
    }

    func testAllVaultDocumentsIncludesFolders() throws {
        let folder = VaultDocument(
            fileName: "Coursework",
            category: CollegePersistence.VaultDocumentCategory.other.rawValue,
            addedAt: .now,
            localRelativePath: "",
            isFolder: true
        )
        let file = VaultDocument(
            fileName: "Notes.pdf",
            category: CollegePersistence.VaultDocumentCategory.other.rawValue,
            addedAt: .now,
            localRelativePath: "notes.colenc",
            isFolder: false
        )
        file.parentFolderID = folder.id
        profileContext.insert(folder)
        profileContext.insert(file)
        try profileContext.save()

        let documents = VaultReadBridge.allVaultDocuments(collegePersistence: .shared)
        XCTAssertEqual(documents.count, 2)
        XCTAssertTrue(documents.contains(where: { $0.isFolder && $0.fileName == "Coursework" }))
        XCTAssertTrue(documents.contains(where: { !$0.isFolder && $0.fileName == "Notes.pdf" }))
    }

    func testDocumentsLinkedToCourseFiltersByCode() throws {
        let linked = VaultDocument(
            fileName: "Syllabus.pdf",
            category: CollegePersistence.VaultDocumentCategory.syllabi.rawValue,
            addedAt: .now,
            localRelativePath: "syl.colenc",
            isFolder: false
        )
        linked.courseCodeLinked = "CSE 191"

        let other = VaultDocument(
            fileName: "Other.pdf",
            category: CollegePersistence.VaultDocumentCategory.other.rawValue,
            addedAt: .now,
            localRelativePath: "other.colenc",
            isFolder: false
        )
        other.courseCodeLinked = "MAT 202"
        profileContext.insert(linked)
        profileContext.insert(other)
        try profileContext.save()

        let matches = VaultReadBridge.documentsLinkedToCourse(
            courseCode: "CSE 191",
            collegePersistence: .shared
        )
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.fileName, "Syllabus.pdf")
    }
}
