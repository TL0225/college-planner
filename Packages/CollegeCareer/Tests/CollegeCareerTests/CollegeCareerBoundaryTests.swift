import CollegeCareer
import XCTest

final class CollegeCareerBoundaryTests: XCTestCase {
    func testBoundaryMetadata() {
        XCTAssertEqual(CollegeCareerBoundary.moduleName, "CollegeCareer")
        XCTAssertEqual(CollegeCareerBoundary.migrationOrderRank, 3)
    }

    func testJobPostingEnrichmentSalaryRange() {
        let text = "Salary: $120,000 - $150,000 per year"
        let range = JobPostingEnrichment.extractSalaryRange(from: text)
        XCTAssertEqual(range?.min, 120_000)
        XCTAssertEqual(range?.max, 150_000)
    }
}
