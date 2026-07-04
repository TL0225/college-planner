// TransferRepositoryDedupeTests.swift
// Feature: Transfer / Tests
// Purpose: Repository upsert dedupe behavior.

import SwiftData
import XCTest
@testable import College

@MainActor
final class TransferRepositoryDedupeTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var repo: TransferRepository!

    override func setUpWithError() throws {
        container = try CollegeModelContainerFactory.makeProfileContainer(inMemory: true)
        context = container.mainContext
        repo = TransferRepository(context: context)
    }

    func testUpsertSameDedupeKeyUpdatesInsteadOfDuplicating() throws {
        var dto = TransferFixtureFactory.sampleDTO()
        _ = try repo.upsert(dto)
        dto.sourceCourseTitle = "Updated Title"
        _ = try repo.upsert(dto)
        let rows = try repo.fetchEquivalencies(targetSchoolID: "target-uni", limit: 100)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.sourceCourseTitle, "Updated Title")
    }

    func testHigherTierWinsOnConflict() throws {
        let community = TransferFixtureFactory.sampleDTO(tier: .community, kind: .githubDataset)
        let official = TransferFixtureFactory.sampleDTO(tier: .official, kind: .assist)
        _ = try repo.upsert(community)
        _ = try repo.upsert(official)
        let row = try repo.fetchEquivalencies(targetSchoolID: "target-uni").first
        XCTAssertEqual(row?.sourceTier, TransferSourceTier.official.rawValue)
    }
}
