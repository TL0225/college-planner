import XCTest
@testable import College

final class CareerResumeWordDiffTests: XCTestCase {
    func testDiffMarksAddedAndRemoved() {
        let segments = CareerResumeWordDiff.diff(
            original: "Led team of engineers",
            revised: "Led cross-functional team of engineers"
        )
        XCTAssertTrue(segments.contains { $0.kind == .added && $0.text.contains("cross-functional") })
        XCTAssertTrue(segments.contains { $0.kind == .unchanged })
    }

    func testIdenticalStringsAllUnchanged() {
        let segments = CareerResumeWordDiff.diff(original: "same text", revised: "same text")
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].kind, .unchanged)
    }
}
