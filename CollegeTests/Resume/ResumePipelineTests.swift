// ResumePipelineTests.swift
// Tests resume snapshot, render model, and Typst generation (Swift fallback path).

import XCTest
@testable import College

@MainActor
final class ResumePipelineTests: XCTestCase {
    func testClassifyLinksPrioritizesLinkedInAndGitHub() {
        let links = ResumeSnapshotBuilder.classifyLinks([
            "https://example.com",
            "https://linkedin.com/in/timothy",
            "https://github.com/timothy",
            "https://portfolio.dev",
        ])

        XCTAssertEqual(links.count, 3)
        XCTAssertEqual(links[0].kind, .linkedIn)
        XCTAssertEqual(links[1].kind, .github)
        XCTAssertEqual(links[2].kind, .website)
    }

    func testRenderModelDropsEmptySections() {
        let snapshot = ResumeSnapshot(
            snapshotID: UUID(),
            sourceProfileID: UUID(),
            capturedAt: Date(),
            profileRevisionToken: "token",
            personal: ResumePersonalInfo(
                name: "Timothy Leung",
                pronouns: nil,
                email: "tim@example.com",
                phone: nil,
                address: nil,
                contactLinks: []
            ),
            education: [],
            experiences: [],
            projects: [],
            skills: []
        )

        let model = ResumeRenderModel.make(
            snapshot: snapshot,
            orderedKinds: [.education, .skills]
        )

        XCTAssertTrue(model.orderedSections.isEmpty)
        XCTAssertEqual(model.includedEmptySectionKinds, [.education, .skills])
    }

    func testTypstEscapingPreservesTemplateMarkup() {
        let escaped = TypstEscaping.escape("AT&T # Labs")
        XCTAssertTrue(escaped.contains("\\#"))
        XCTAssertFalse(escaped.contains("== "))
    }

    func testStandardTemplateGeneratesTypstSource() {
        let snapshot = ResumeSnapshot(
            snapshotID: UUID(),
            sourceProfileID: UUID(),
            capturedAt: Date(),
            profileRevisionToken: "token",
            personal: ResumePersonalInfo(
                name: "Timothy Leung 梁",
                pronouns: nil,
                email: "tim@example.com",
                phone: nil,
                address: nil,
                contactLinks: []
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
            experiences: [],
            projects: [],
            skills: ["Swift", "Rust"]
        )

        let model = ResumeRenderModel.make(snapshot: snapshot, orderedKinds: [.education, .skills])
        let source = StandardATSTemplate().makeTypstSource(model)

        XCTAssertTrue(source.contains("Timothy Leung"))
        XCTAssertTrue(source.contains("== Education"))
        XCTAssertTrue(source.contains("== Skills"))
    }

    func testFallbackPDFCompilation() throws {
        let source = """
        = Test Resume
        Hello world
        """
        let data = try CollegeTypst.compilePDF(typstSource: source)
        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
    }
}
