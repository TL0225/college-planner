import XCTest
@testable import College

final class CareerResumeDateParserTests: XCTestCase {
    func testParsesMultiDashInsmedHeading() {
        let heading = "Cybersecurity Analyst Intern – Insmed Incorporated – Remote June 2025 – August 2025"
        let range = CareerResumeDateParser.parseDateRange(from: heading)
        XCTAssertNotNil(range)

        let start = range!.start
        let end = range!.end
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.year, from: start), 2025)
        XCTAssertEqual(cal.component(.month, from: start), 6)
        XCTAssertEqual(cal.component(.year, from: end), 2025)
        XCTAssertEqual(cal.component(.month, from: end), 8)
    }

    func testParsesYearOnlyRange() {
        let heading = "Real Estate Investment Intern — Project Destined — Remote September 2024 – December 2024"
        let range = CareerResumeDateParser.parseDateRange(from: heading)
        XCTAssertNotNil(range)
        XCTAssertEqual(Calendar.current.component(.year, from: range!.start), 2024)
        XCTAssertEqual(Calendar.current.component(.month, from: range!.end), 12)
    }

    func testExperienceAnalyzerCountsTimothyResumeHeadings() {
        var profile = CareerResumeStructuredProfile()
        profile.experience = [
            .init(
                headingLines: ["Cybersecurity Analyst Intern – Insmed Incorporated – Remote June 2025 – August 2025"],
                bullets: []
            ),
            .init(
                headingLines: ["Real Estate Investment Intern — Project Destined — Remote September 2024 – December 2024"],
                bullets: []
            ),
            .init(
                headingLines: ["Technical Support Analyst Intern — Computer Care and Learning — Remote June 2022 – July 2022"],
                bullets: []
            ),
        ]
        let result = CareerExperienceAnalyzer.analyze(
            jdText: "minimum of 3 years of biotech/pharma product promotion",
            structuredProfile: profile
        )
        XCTAssertGreaterThan(result.candidateMonths, 5)
        XCTAssertEqual(result.requiredYearsMin, 3)
        XCTAssertNotNil(result.gapNote)
    }
}
