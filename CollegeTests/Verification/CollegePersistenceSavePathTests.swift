// CollegePersistenceSavePathTests.swift
// Snow Leopard V&V: save() must not invoke full refreshAll (P2).

import XCTest
@testable import College

@MainActor
final class CollegePersistenceSavePathTests: PersistenceTestCase {
    func testSaveIncrementsProfileCachesOnly() {
        let persistence = CollegePersistence.shared
        let beforeRefreshAll = snapshotRefreshAllCount()
        let beforeProfile = snapshotRefreshProfileCount()

        persistence.save()

        XCTAssertEqual(snapshotRefreshAllCount(), beforeRefreshAll)
        XCTAssertGreaterThan(snapshotRefreshProfileCount(), beforeProfile)
    }

    private func snapshotRefreshAllCount() -> Int {
        SnowLeopardHealthMetrics.snapshot().refreshAllCallCount
    }

    private func snapshotRefreshProfileCount() -> Int {
        SnowLeopardHealthMetrics.snapshot().refreshProfileCachesCallCount
    }
}
