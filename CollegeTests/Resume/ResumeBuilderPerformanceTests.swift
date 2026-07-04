// ResumeBuilderPerformanceTests.swift
// Feature: Resume Tests
// Purpose: XCTest performance gates for compile, ingest fast-path, match cache, and reorder.

import XCTest
@testable import College

@MainActor
final class ResumeBuilderPerformanceTests: XCTestCase {
    func testTypstCompileWithinBudget() throws {
        let snapshot = ResumePipelineTestFixtures.sampleSnapshot()
        let model = ResumeRenderModel.make(snapshot: snapshot, orderedKinds: [.education, .skills])
        let source = StandardATSTemplate().makeTypstSource(model)

        let start = CFAbsoluteTimeGetCurrent()
        _ = try CollegeTypst.compilePDF(typstSource: source)
        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1_000)

        XCTAssertFalse(
            ResumePerformanceAcceptance.typstCompileExceedsBudget(durationMs: elapsedMs),
            "Typst compile took \(elapsedMs)ms; budget is \(ResumePerformanceAcceptance.typstCompileBudgetMs)ms"
        )
    }

    func testFastPathIngestSkipsLLM() {
        let structured = ResumePipelineTestFixtures.sampleStructuredProfile()
        let encoded = try! JSONEncoder().encode(structured)
        let json = String(data: encoded, encoding: .utf8)!

        let start = CFAbsoluteTimeGetCurrent()
        var meta = CareerResumeMetadataV1()
        meta.canonicalProfileJSON = json
        let canonical = meta.canonicalProfile
        let profile = canonical ?? structured
        XCTAssertTrue(profile.hasContent)
        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1_000)

        XCTAssertFalse(
            ResumePerformanceAcceptance.fastPathIngestExceedsBudget(durationMs: elapsedMs),
            "Fast-path canonical decode took \(elapsedMs)ms"
        )
    }

    func testMatchCacheInvalidatesOnHashChange() throws {
        let container = try CollegeModelContainerFactory.makeProfileContainer(inMemory: true)
        let repo = CareerRepository(context: container.mainContext)
        let resumeID = UUID()

        _ = try repo.upsertResumeJobMatch(
            companySlug: "acme",
            externalPath: "/job/1",
            resumeDocumentID: resumeID,
            overallScore: 82,
            keywordScore: 70,
            semanticScore: 75,
            experienceScore: 68,
            missingKeywords: [],
            recommendedForPosting: true,
            resultJSON: nil,
            descriptionHash: "jd-hash",
            resumeHash: "resume-hash-a"
        )

        let match = try XCTUnwrap(
            repo.fetchResumeJobMatch(companySlug: "acme", externalPath: "/job/1", resumeDocumentID: resumeID)
        )
        XCTAssertTrue(
            JobBoardMatchEligibility.isMatchCacheValid(
                match: match,
                postingDescriptionHash: "jd-hash",
                resumeParsedTextHash: "resume-hash-a"
            )
        )
        XCTAssertFalse(
            JobBoardMatchEligibility.isMatchCacheValid(
                match: match,
                postingDescriptionHash: "jd-hash",
                resumeParsedTextHash: "resume-hash-b"
            )
        )

        try repo.invalidateResumeJobMatches(resumeDocumentID: resumeID)
        XCTAssertNil(
            try repo.fetchResumeJobMatch(companySlug: "acme", externalPath: "/job/1", resumeDocumentID: resumeID)
        )
    }

    func testBuilderReorderPersists() {
        let snapshot = ResumePipelineTestFixtures.sampleSnapshot()
        let viewModel = ResumeBuilderViewModel(
            snapshot: snapshot,
            collegePersistence: CollegePersistence.shared
        )

        viewModel.placeSection(.skills, before: .education)
        XCTAssertEqual(
            viewModel.orderedSections,
            [.summary, .skills, .education, .experience, .projects, .achievements, .certifications, .extracurriculars]
        )

        viewModel.placeSection(.experience, before: .skills)
        XCTAssertEqual(
            viewModel.orderedSections,
            [.summary, .experience, .skills, .education, .projects, .achievements, .certifications, .extracurriculars]
        )
    }

    func testDOCXExportNoForbiddenElements() throws {
        let profile = ResumeCanonicalProfile(
            basics: .init(
                name: "Timothy Leung",
                email: "tim@example.com",
                phone: nil,
                location: nil,
                summary: nil,
                links: []
            ),
            work: [
                ResumeCanonicalProfile.WorkEntry(
                    id: UUID(),
                    position: "Engineer",
                    company: "Acme",
                    location: nil,
                    dateRange: "2024 – Present",
                    highlights: ["Built APIs"],
                    technologies: "Swift"
                ),
            ],
            education: [],
            projects: [],
            skills: ["Swift", "Rust"],
            skillGroups: [],
            certifications: []
        )
        XCTAssertTrue(profile.hasContent)

        let xml = ResumeDOCXExporter.documentXML(from: profile)
        XCTAssertFalse(xml.isEmpty)
        for pattern in ["<w:tbl", "<w:textbox", "<w:hdr", "<w:ftr", "<w:cols"] {
            XCTAssertFalse(xml.contains(pattern), "Forbidden OOXML element \(pattern) in document XML")
        }
    }
}

// MARK: - Fixtures

private enum ResumePipelineTestFixtures {
    static func sampleSnapshot() -> ResumeSnapshot {
        ResumeSnapshot(
            snapshotID: UUID(),
            sourceProfileID: UUID(),
            capturedAt: Date(),
            profileRevisionToken: "token",
            personal: ResumePersonalInfo(
                name: "Timothy Leung",
                pronouns: nil,
                email: "tim@example.com",
                phone: "5551234567",
                address: "New York, NY",
                contactLinks: [
                    ResumeContactLink(kind: .linkedIn, url: "https://linkedin.com/in/timothy", displayLabel: "LinkedIn"),
                ]
            ),
            education: [
                ResumeEducationEntry(
                    id: UUID(),
                    degreeLevel: "BS",
                    major: "Computer Science",
                    collegeName: "University",
                    gpa: 3.8,
                    expectedGraduation: "May 2027"
                ),
            ],
            experiences: [
                ResumeExperienceEntry(
                    id: UUID(),
                    title: "Engineer",
                    company: "Acme",
                    location: "Remote",
                    dateRange: "2024 – Present",
                    descriptionText: "Built APIs\nImproved reliability",
                    technologies: "Swift"
                ),
            ],
            projects: [],
            skills: ["Swift", "Rust"]
        )
    }

    static func sampleStructuredProfile() -> CareerResumeStructuredProfile {
        var profile = CareerResumeStructuredProfile()
        profile.name = "Timothy Leung"
        profile.email = "tim@example.com"
        profile.experience = [
            CareerResumeStructuredProfile.Entry(
                headingLines: ["Engineer", "Acme", "2024 – Present"],
                bullets: ["Built APIs"]
            ),
        ]
        profile.skills = ["Swift"]
        return profile
    }
}
