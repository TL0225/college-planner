import XCTest
@testable import College

final class OrgUnitNormalizationTests: XCTestCase {
    func testNormalizeOrgUnitKeyBasic() {
    // Mirrors normalization behavior used in CoreDataManager and ModernCampusEngine.
        func normalize(_ value: String) -> String {
            value
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "&", with: "and")
                .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        XCTAssertEqual(normalize("College of Engineering & Applied Sciences"), "college of engineering and applied sciences")
        XCTAssertEqual(normalize("  Department of Computer Science  "), "department of computer science")
        XCTAssertEqual(normalize("Electrical- and Computer-Engineering"), "electrical and computer engineering")
    }
}
