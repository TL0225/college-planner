// CareerBoardManualApplicationMatchTests.swift
// Feature: Career
// Purpose: Guard G10 — manual board applications use applicationID cache key.

import SwiftData
import XCTest
import CollegeCareer
@testable import College

@MainActor
final class CareerBoardManualApplicationMatchTests: XCTestCase {
    func testManualApplicationMatch_usesApplicationIDKey() throws {
        let container = try CollegeModelContainerFactory.makeProfileContainer(inMemory: true)
        let repo = CareerRepository(context: container.mainContext)

        let application = JobApplication(id: UUID(), statusRaw: CareerApplicationStatus.interested.rawValue)
        application.company = "Acme"
        application.title = "Engineer"
        application.jobDescriptionText = "Build APIs with Swift."
        container.mainContext.insert(application)
        try container.mainContext.save()

        let resumeID = UUID()
        let path = CareerRepository.CareerResumeJobMatchKey.manualApplicationExternalPath(application.id)
        let slug = CareerRepository.CareerResumeJobMatchKey.companySlug(for: application)

        _ = try repo.upsertResumeJobMatch(
            companySlug: slug,
            externalPath: path,
            resumeDocumentID: resumeID,
            overallScore: 78,
            keywordScore: 70,
            semanticScore: 72,
            experienceScore: 65,
            missingKeywords: ["kubernetes"],
            recommendedForPosting: true,
            resultJSON: nil,
            descriptionHash: "jd-hash",
            resumeHash: "resume-hash"
        )

        let match = try repo.recommendedMatch(companySlug: slug, externalPath: path)
        XCTAssertEqual(match?.overallScore, 78)
        XCTAssertEqual(match?.resumeDocumentID, resumeID)
    }
}
