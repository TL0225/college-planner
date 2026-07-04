// VaultHierarchyIntegrityTests.swift
// Snow Leopard V&V: parentFolderID ↔ parentFolder consistency (DM-R1).

import SwiftData
import XCTest
@testable import College

@MainActor
final class VaultHierarchyIntegrityTests: PersistenceTestCase {
    func testCreateFolderAndChildMaintainsHierarchy() throws {
        let repo = VaultRepository(context: profileContext)
        let folder = try XCTUnwrap(repo.createVaultFolder(name: "Syllabi", parentFolderID: nil))
        let child = VaultDocument(
            fileName: "notes.pdf",
            category: CollegePersistence.VaultDocumentCategory.other.rawValue,
            localRelativePath: "notes.colenc",
            isFolder: false
        )
        child.parentFolderID = folder.id
        repo.syncParentFolderRelationship(for: child)
        profileContext.insert(child)
        try profileContext.save()

        XCTAssertEqual(try repo.hierarchyViolations(), [])
        SnowLeopardHealthMetrics.recordVaultHierarchyViolations(0)
    }

    func testMoveUpdatesParentRelationship() throws {
        let repo = VaultRepository(context: profileContext)
        let root = try XCTUnwrap(repo.createVaultFolder(name: "Root", parentFolderID: nil))
        let nested = try XCTUnwrap(repo.createVaultFolder(name: "Nested", parentFolderID: root.id))
        try repo.moveVaultDocument(id: nested.id, toFolderID: nil)
        try profileContext.save()

        XCTAssertEqual(try repo.hierarchyViolations(), [])
    }

    func testSyncRepairsMissingRelationship() throws {
        let repo = VaultRepository(context: profileContext)
        let folder = try XCTUnwrap(repo.createVaultFolder(name: "Folder", parentFolderID: nil))
        let doc = VaultDocument(
            fileName: "a.pdf",
            category: CollegePersistence.VaultDocumentCategory.other.rawValue,
            localRelativePath: "a.colenc",
            isFolder: false
        )
        doc.parentFolderID = folder.id
        profileContext.insert(doc)
        try profileContext.save()

        doc.parentFolder = nil
        repo.syncParentFolderRelationship(for: doc)
        try profileContext.save()

        XCTAssertEqual(doc.parentFolder?.id, folder.id)
        XCTAssertTrue(try repo.hierarchyViolations().isEmpty)
    }
}
