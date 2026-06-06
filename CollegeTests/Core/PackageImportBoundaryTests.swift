import XCTest

final class PackageImportBoundaryTests: XCTestCase {
    func testForbiddenCrossPackageImportWouldFailGate() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let probe = repoRoot
            .appendingPathComponent("Packages/CollegeCalendar/Sources/CollegeCalendar/_ADR004ImportProbe.swift")
        defer { try? FileManager.default.removeItem(at: probe) }

        try """
        import CollegeAcademics
        """.write(to: probe, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            repoRoot.appendingPathComponent("scripts/check-feature-imports.sh").path,
            "fail",
        ]
        process.currentDirectoryURL = repoRoot

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.launch()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertNotEqual(process.terminationStatus, 0, "Expected fail mode to reject cross-package import")
        XCTAssertTrue(output.contains("CollegeAcademics"), output)
    }
}
