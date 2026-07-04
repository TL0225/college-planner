import XCTest
@testable import College
import CollegeCareer

final class CareerTransferableSkillsExpanderTests: XCTestCase {
    func testDirectSkillInRecentBullet() {
        var profile = CareerResumeStructuredProfile()
        profile.experience = [
            .init(
                headingLines: ["Engineer", "2023 – Present"],
                bullets: ["Built customer support tooling with Swift"]
            ),
        ]
        let result = CareerTransferableSkillsExpander.analyze(
            requiredSkills: ["swift"],
            profile: profile,
            resumeText: ""
        )
        XCTAssertEqual(result.entries.first?.status, "direct")
    }

    func testTransferableAdjacentSkill() {
        var profile = CareerResumeStructuredProfile()
        profile.skills = ["communication", "crm"]
        let result = CareerTransferableSkillsExpander.analyze(
            requiredSkills: ["customer service"],
            profile: profile,
            resumeText: "communication crm"
        )
        XCTAssertEqual(result.entries.first?.status, "transferable")
        XCTAssertGreaterThan(result.transferableScore, 0)
    }

    func testMissingSkill() {
        let result = CareerTransferableSkillsExpander.analyze(
            requiredSkills: ["kubernetes"],
            profile: CareerResumeStructuredProfile(),
            resumeText: "swift ios"
        )
        XCTAssertEqual(result.entries.first?.status, "missing")
        XCTAssertEqual(result.transferableScore, 0)
    }
}
