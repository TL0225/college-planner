// CareerMatchCacheRevisionTests.swift
// Feature: Career
// Purpose: Guard G2 — career revision bumps when match cache writes.

import SwiftData
import XCTest
@testable import College

@MainActor
final class CareerMatchCacheRevisionTests: XCTestCase {
    func testUpsertResumeJobMatch_bumpsCareerRevision() throws {
        let container = try CollegeModelContainerFactory.makeProfileContainer(inMemory: true)
        let before = CollegePersistence.shared.careerDidChangeToken
        let repo = CareerRepository(context: container.mainContext)
        _ = try repo.upsertResumeJobMatch(
            companySlug: "acme",
            externalPath: "/job/1",
            resumeDocumentID: UUID(),
            overallScore: 70,
            keywordScore: 60,
            semanticScore: 65,
            experienceScore: 55,
            missingKeywords: ["swift"],
            recommendedForPosting: true,
            resultJSON: nil,
            descriptionHash: "hash-a",
            resumeHash: "resume-a"
        )
        XCTAssertGreaterThan(CollegePersistence.shared.careerDidChangeToken, before)
    }
}
