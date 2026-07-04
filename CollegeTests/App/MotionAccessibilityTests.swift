// MotionAccessibilityTests.swift
// M30-087 — Reduce Motion gates for repeating animations.

import XCTest

final class MotionAccessibilityTests: XCTestCase {
    private let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    func testRepeatForeverAnimationsAreGated() throws {
        let featuresDir = repoRoot.appendingPathComponent("College")
        let files = try FileManager.default.subpathsOfDirectory(atPath: featuresDir.path)
            .filter { $0.hasSuffix(".swift") }

        var violations: [String] = []
        for relative in files {
            let url = featuresDir.appendingPathComponent(relative)
            let source = try String(contentsOf: url, encoding: .utf8)
            guard source.contains("repeatForever") else { continue }

            let gated =
                source.contains("motionReduced")
                || source.contains("reduceMotion")
                || source.contains("CollegeReduceMotionGate")
                || source.contains("accessibilityReduceMotion")

            if !gated {
                violations.append(relative)
            }
        }

        XCTAssertTrue(
            violations.isEmpty,
            "repeatForever must be gated by Reduce Motion:\n" + violations.joined(separator: "\n")
        )
    }

    func testCollegeInteractiveSurfaceExists() throws {
        let path = repoRoot.appendingPathComponent("College/Core/DesignSystem/CollegeInteractiveSurface.swift")
        let source = try String(contentsOf: path, encoding: .utf8)
        XCTAssertTrue(source.contains("struct CollegeInteractiveSurface"))
        XCTAssertTrue(source.contains("CollegeReduceMotionGate"))
    }

    func testCollegeMotionTokensExist() throws {
        let path = repoRoot.appendingPathComponent("College/Core/DesignSystem/CollegeMotion.swift")
        let source = try String(contentsOf: path, encoding: .utf8)
        XCTAssertTrue(source.contains("enum CollegeMotion"))
        XCTAssertTrue(source.contains("cursorSpring"))
        XCTAssertTrue(source.contains("pressSpring"))
    }

    func testCollegeInteractiveSurfaceUsedInShellHotPaths() throws {
        let paths = [
            "College/App/SidebarView.swift",
            "College/Core/DesignSystem/ToolbarMetrics.swift",
            "College/Features/Career/Applications/Views/ApplicationTrackerView.swift",
        ]
        for relative in paths {
            let path = repoRoot.appendingPathComponent(relative)
            let source = try String(contentsOf: path, encoding: .utf8)
            XCTAssertTrue(
                source.contains("collegeInteractiveSurface") || source.contains("CollegeInteractiveSurface"),
                "Expected CollegeInteractiveSurface in \(relative)"
            )
        }
    }
}
