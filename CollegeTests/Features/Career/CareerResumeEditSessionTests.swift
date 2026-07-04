import XCTest
@testable import College
import CollegeCareer

@MainActor
final class CareerResumeEditSessionTests: XCTestCase {
    func testExportProfileAppliesAcceptedSuggestion() {
        var profile = CareerResumeStructuredProfile()
        profile.experience = [
            .init(headingLines: ["Engineer"], bullets: ["Helped build APIs"]),
        ]
        let suggestion = CareerResumeSuggestion(
            entryHeading: "Engineer",
            originalBullet: "Helped build APIs",
            proposedBullet: "Delivered REST APIs",
            rationale: "Stronger verb",
            type: .actionVerbUpgrade,
            tier: .safe,
            scoreDeltaEstimate: 4
        )
        let session = CareerResumeEditSession(
            sourceDocumentID: UUID(),
            jobTitle: "Backend Engineer",
            companyName: "Acme",
            platform: .workday,
            baseProfile: profile,
            suggestions: [suggestion],
            liveMatchScoreBefore: 40
        )
        session.decisions[suggestion.id] = .accepted
        let exported = session.exportProfile()
        XCTAssertEqual(exported.experience.first?.bullets.first, "Delivered REST APIs")
        XCTAssertTrue(session.previewText().contains("Delivered REST APIs"))
    }

    func testApplyAllSafeSkipsVerifyTier() {
        let safe = CareerResumeSuggestion(
            entryHeading: "A",
            originalBullet: "a",
            proposedBullet: "b",
            rationale: "ok",
            type: .actionVerbUpgrade,
            tier: .safe
        )
        let verify = CareerResumeSuggestion(
            entryHeading: "A",
            originalBullet: "c",
            proposedBullet: "d",
            rationale: "check",
            type: .keywordInjection,
            tier: .verify
        )
        let session = CareerResumeEditSession(
            sourceDocumentID: UUID(),
            jobTitle: "Role",
            companyName: "Co",
            platform: .workday,
            baseProfile: CareerResumeStructuredProfile(),
            suggestions: [safe, verify]
        )
        session.applyAllSafe()
        XCTAssertEqual(session.decisions[safe.id], .accepted)
        XCTAssertNil(session.decisions[verify.id])
    }
}
