// UserDefaultsWindowAutosaveCleanupTests.swift
// Feature: Shared
// Purpose: Shared module — UserDefaultsWindowAutosaveCleanupTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class UserDefaultsWindowAutosaveCleanupTests: XCTestCase {

    func testPurgePolicy_removesSwiftUIModifiedContentKeys() {
        let key = "NSWindow Frame SwiftUI.ModifiedContent<Foo><Bar>"
        XCTAssertTrue(UserDefaultsWindowAutosaveCleanup.matchesUnstablePurgePolicy(key: key))
    }

    func testPurgePolicy_removesLegacyPersistenceWindowKeys() {
        let key = "NSWindow Frame SwiftUI.ModifiedContent<College." + "CollegePersistence" + "Manager>-1-AppWindow-1"
        XCTAssertTrue(UserDefaultsWindowAutosaveCleanup.matchesUnstablePurgePolicy(key: key))
    }

    func testPurgePolicy_removesOversizedSplitKeys() {
        let key = "NSSplitView Subview Frames " + String(repeating: "x", count: 600)
        XCTAssertTrue(UserDefaultsWindowAutosaveCleanup.matchesUnstablePurgePolicy(key: key))
    }

    func testPurgePolicy_preservesMainWindowAutosave() {
        let key = "NSWindow Frame Stable-\(AutosaveNames.mainWindow)-extra"
        XCTAssertFalse(UserDefaultsWindowAutosaveCleanup.matchesUnstablePurgePolicy(key: key))
    }

    func testPurgePolicy_ignoresNonWindowKeys() {
        XCTAssertFalse(UserDefaultsWindowAutosaveCleanup.matchesUnstablePurgePolicy(key: "College.some.setting"))
    }
}
