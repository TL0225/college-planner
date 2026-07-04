// CareerPipelineEndToEndSmokeTests.swift
// Feature: Career
// Purpose: Smoke tests for ATS pipeline guards G1-G7.

import SwiftData
import XCTest
@testable import College

@MainActor
final class CareerPipelineEndToEndSmokeTests: XCTestCase {
    func testCareerResumeHashing_normalizesBeforeHashing() {
        let a = CareerResumeHashing.hash(normalizedPlainText: "Hello\nWorld")
        let b = CareerResumeHashing.hash(normalizedPlainText: "  hello \n world ")
        XCTAssertEqual(a, b)
    }

    func testParserCompliance_flagsSparseText() {
        let report = CareerResumeParserCompliance.analyze(plainText: "Hi", pageCount: 1, usedOCR: false)
        XCTAssertEqual(report.status, .critical)
        XCTAssertLessThan(report.healthPercent, 70)
    }

    func testCareerResumeMetadata_decodesLegacyATSScore() throws {
        let json = """
        {"kind":"general","archived":false,"atsScorePercent":82}
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let meta = try JSONDecoder().decode(CareerResumeMetadataV1.self, from: data)
        XCTAssertEqual(meta.parserHealthPercent, 82)
    }

    func testApplyJobBoardDetail_writesDescriptionHash() throws {
        let container = try CollegeModelContainerFactory.makeProfileContainer(inMemory: true)
        let repo = CareerRepository(context: container.mainContext)
        let posting = WorkdayJobPosting(companySlug: "acme", externalId: "job-1")
        posting.externalPath = "/job/1"
        container.mainContext.insert(posting)
        try container.mainContext.save()

        let detail = ScrapedJobDetail(
            title: "Engineer",
            descriptionPlain: "Build APIs with Swift and Workday integrations.",
            requirementsPlain: nil,
            locationDisplay: "Remote",
            filterLocations: [],
            postedAt: nil,
            postedOnDisplay: nil,
            workModel: nil,
            jobTypeText: nil,
            timeType: nil,
            salaryText: nil
        )
        try repo.applyJobBoardDetail(posting: posting, detail: detail)

        XCTAssertNotNil(posting.descriptionHash)
        XCTAssertEqual(
            posting.descriptionHash,
            CareerResumeHashing.hash(jobDescriptionPlain: detail.descriptionPlain)
        )
    }

    func testResumeJobMatch_recommendedIsExclusive() throws {
        let container = try CollegeModelContainerFactory.makeProfileContainer(inMemory: true)
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
        _ = try repo.upsertResumeJobMatch(
            companySlug: "acme",
            externalPath: "/job/1",
            resumeDocumentID: UUID(),
            overallScore: 82,
            keywordScore: 80,
            semanticScore: 78,
            experienceScore: 70,
            missingKeywords: ["uat"],
            recommendedForPosting: true,
            resultJSON: nil,
            descriptionHash: "hash-a",
            resumeHash: "resume-b"
        )

        let matches = try repo.fetchResumeJobMatches(companySlug: "acme", externalPath: "/job/1")
        XCTAssertEqual(matches.filter(\.recommendedForPosting).count, 1)
        XCTAssertEqual(matches.first?.overallScore, 82)
    }

    func testCareerSignal_emptyBeforeMinimumJobs() {
        let snapshot = CareerSignalAggregator.snapshot()
        XCTAssertLessThan(snapshot.scoredJobCount, CareerSignalAggregator.minimumScoredJobs)
    }

    func testATSAdviceValidator_rejectsGenericTip() {
        XCTAssertNil(CareerATSAdviceValidator.validatedTip("Add more keywords to your resume."))
        XCTAssertNotNil(CareerATSAdviceValidator.validatedTip("Mention UAT oversight — it appears 4 times in this JD and is missing from your resume."))
    }

    func testJDChangeInvalidatesCache() throws {
        let container = try CollegeModelContainerFactory.makeProfileContainer(inMemory: true)
        let repo = CareerRepository(context: container.mainContext)
        let posting = WorkdayJobPosting(companySlug: "acme", externalId: "job-1")
        posting.externalPath = "/job/1"
        container.mainContext.insert(posting)
        try container.mainContext.save()

        let resumeID = UUID()
        _ = try repo.upsertResumeJobMatch(
            companySlug: "acme",
            externalPath: "/job/1",
            resumeDocumentID: resumeID,
            overallScore: 70,
            keywordScore: 60,
            semanticScore: 65,
            experienceScore: 55,
            missingKeywords: ["swift"],
            recommendedForPosting: true,
            resultJSON: nil,
            descriptionHash: "old-hash",
            resumeHash: "resume-a"
        )

        let detail = ScrapedJobDetail(
            title: "Engineer",
            descriptionPlain: "Updated description with Kubernetes and Go.",
            requirementsPlain: nil,
            locationDisplay: "Remote",
            filterLocations: [],
            postedAt: nil,
            postedOnDisplay: nil,
            workModel: nil,
            jobTypeText: nil,
            timeType: nil,
            salaryText: nil
        )
        try repo.applyJobBoardDetail(posting: posting, detail: detail)

        let matches = try repo.fetchResumeJobMatches(companySlug: "acme", externalPath: "/job/1")
        XCTAssertTrue(matches.isEmpty)
        XCTAssertEqual(
            posting.descriptionHash,
            CareerResumeHashing.hash(jobDescriptionPlain: detail.descriptionPlain)
        )
    }

    func testResumeHashChangeRescores_newMatchUsesUpdatedHash() throws {
        let container = try CollegeModelContainerFactory.makeProfileContainer(inMemory: true)
        let repo = CareerRepository(context: container.mainContext)
        let resumeID = UUID()

        _ = try repo.upsertResumeJobMatch(
            companySlug: "acme",
            externalPath: "/job/2",
            resumeDocumentID: resumeID,
            overallScore: 60,
            keywordScore: 55,
            semanticScore: 50,
            experienceScore: 45,
            missingKeywords: ["python"],
            recommendedForPosting: true,
            resultJSON: nil,
            descriptionHash: "jd-hash",
            resumeHash: "resume-v1"
        )

        let updated = try repo.upsertResumeJobMatch(
            companySlug: "acme",
            externalPath: "/job/2",
            resumeDocumentID: resumeID,
            overallScore: 72,
            keywordScore: 68,
            semanticScore: 70,
            experienceScore: 60,
            missingKeywords: ["docker"],
            recommendedForPosting: true,
            resultJSON: nil,
            descriptionHash: "jd-hash",
            resumeHash: "resume-v2"
        )

        XCTAssertEqual(updated.resumeHashAtScore, "resume-v2")
        XCTAssertEqual(updated.overallScore, 72)
    }
}
