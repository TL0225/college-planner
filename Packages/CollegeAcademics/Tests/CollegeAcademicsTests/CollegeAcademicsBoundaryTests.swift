import CollegeAcademics
import XCTest

final class CollegeAcademicsBoundaryTests: XCTestCase {
    func testBoundaryMetadata() {
        XCTAssertEqual(CollegeAcademicsBoundary.moduleName, "CollegeAcademics")
        XCTAssertEqual(CollegeAcademicsBoundary.migrationOrderRank, 2)
    }

    func testGPAFormattingFractionText() {
        XCTAssertEqual(GPAFormatting.fractionText(gpa: 3.5), "3.500 / 4.000")
        XCTAssertEqual(GPAFormatting.fractionText(gpa: nil), "— / 4.000")
    }
}
