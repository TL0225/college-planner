// ProfileReadBridgeTests.swift
// Feature: Profile
// Purpose: Profile module — ProfileReadBridgeTests.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import XCTest
@testable import College

@MainActor
final class ProfileReadBridgeTests: PersistenceTestCase {
    func testShellSnapshotFromStoreProfile() throws {
        let profile = Profile(name: "Alex Morgan")
        profile.collegeName = "Example University"
        profileContext.insert(profile)
        try profileContext.save()

        let shell = ProfileReadBridge.shellSnapshot(collegePersistence: .shared)
        XCTAssertEqual(shell.displayName, "Alex Morgan")
        XCTAssertEqual(shell.collegeName, "Example University")
        XCTAssertEqual(shell.initials, "AM")
    }
}
