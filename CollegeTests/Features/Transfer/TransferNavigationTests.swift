// TransferNavigationTests.swift
// Feature: Transfer / Tests
// Purpose: Sidebar navigation and toolbar metadata coverage.

import XCTest
@testable import College

final class TransferNavigationTests: XCTestCase {
    func testTransferDatabaseAppPageRawValue() {
        XCTAssertEqual(AppPage.transferDatabase.rawValue, "Transfer Database")
        XCTAssertEqual(AppPage(rawValue: "Transfer Database"), .transferDatabase)
    }

    func testTransferDatabaseToolbarMetadata() {
        let entry = AppPageToolbarMetadata.entry(for: .transferDatabase)
        XCTAssertTrue(entry.hasDedicatedToolbarChrome)
        XCTAssertEqual(entry.toolbarProviderTypeName, "TransferToolbarProvider")
        XCTAssertEqual(entry.toolbarContentTypeName, "TransferToolbarContent")
    }

    func testTransferDeepLinkAliases() {
        XCTAssertTrue(
            CollegeInboundURLDispatcher.handle(
                URL(string: "college://tab/transfer")!,
                spotifyHandler: { _ in }
            )
        )
        XCTAssertTrue(
            CollegeInboundURLDispatcher.handle(
                URL(string: "college://tab/transfer-database")!,
                spotifyHandler: { _ in }
            )
        )
    }
}
