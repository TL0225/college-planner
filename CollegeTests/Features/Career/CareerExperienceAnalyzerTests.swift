import XCTest
@testable import College

final class CareerExperienceAnalyzerTests: XCTestCase {
    func testParseRequiredYearsRange() {
        let jd = "We need 3–5 years of professional software engineering experience."
        let result = CareerExperienceAnalyzer.analyze(jdText: jd, structuredProfile: nil)
        XCTAssertEqual(result.requiredYearsMin, 3)
        XCTAssertEqual(result.requiredYearsMax, 5)
    }

    func testParseMinimumYears() {
        let jd = "Minimum 4 years experience with Swift required."
        let result = CareerExperienceAnalyzer.analyze(jdText: jd, structuredProfile: nil)
        XCTAssertEqual(result.requiredYearsMin, 4)
    }

    func testCandidateMonthsFromStructuredProfile() {
        var profile = CareerResumeStructuredProfile()
        profile.experience = [
            .init(headingLines: ["Engineer · Jun 2020 – Present"], bullets: ["Built apps"]),
            .init(headingLines: ["Intern · 2019 – 2020"], bullets: ["Helped team"]),
        ]
        let result = CareerExperienceAnalyzer.analyze(jdText: "2+ years required", structuredProfile: profile)
        XCTAssertGreaterThan(result.candidateMonths, 12)
        XCTAssertNil(result.gapNote)
    }

    func testGapNoteWhenUnderqualified() {
        var profile = CareerResumeStructuredProfile()
        profile.experience = [
            .init(headingLines: ["Intern", "2024 – Present"], bullets: []),
        ]
        let result = CareerExperienceAnalyzer.analyze(jdText: "8+ years of experience", structuredProfile: profile)
        XCTAssertNotNil(result.gapNote)
        XCTAssertLessThan(result.score, 75)
    }
}
