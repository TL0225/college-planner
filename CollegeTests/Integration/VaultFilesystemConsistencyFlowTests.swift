// VaultFilesystemConsistencyFlowTests.swift
// Snow Leopard flow #5: vault delete removes DB row.

import SwiftData
import XCTest
@testable import College

@MainActor
final class VaultFilesystemConsistencyFlowTests: PersistenceTestCase {
    func testDeleteVaultDocumentRemovesRow() throws {
        let repo = VaultRepository(context: profileContext)
        let doc = VaultDocument(
            fileName: "flow.pdf",
            category: CollegePersistence.VaultDocumentCategory.other.rawValue,
            localRelativePath: "flow.colenc",
            isFolder: false
        )
        profileContext.insert(doc)
        try profileContext.save()
        XCTAssertEqual(try repo.fetchDocumentCount(), 1)

        try repo.deleteVaultDocument(id: doc.id)
        try profileContext.save()
        XCTAssertEqual(try repo.fetchDocumentCount(), 0)
    }
}
