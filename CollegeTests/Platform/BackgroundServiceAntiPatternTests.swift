// BackgroundServiceAntiPatternTests.swift
// Grep-based architecture gates for background service anti-patterns.

import XCTest

final class BackgroundServiceAntiPatternTests: XCTestCase {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testCollegeAppDoesNotUseStartTrackedServiceTask() throws {
        let source = try String(
            contentsOf: repoRoot.appendingPathComponent("College/App/CollegeApp.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(source.contains("startTrackedServiceTask"))
    }

    func testNSBackgroundActivitySchedulerOnlyInAllowlist() throws {
        let collegeDir = repoRoot.appendingPathComponent("College")
        let allowlist: Set<String> = [
            "College/Core/Platform/Services/BackgroundServiceScheduler.swift",
            "College/Core/Platform/Services/BackgroundServiceSchedulerIDs.swift",
            "College/Core/Platform/Services/BackgroundServiceDeprecatedShims.swift",
            "College/App/BackgroundTaskCompliance.swift",
        ]
        let enumerator = FileManager.default.enumerator(
            at: collegeDir,
            includingPropertiesForKeys: nil
        )!
        var violations: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let rel = url.path.replacingOccurrences(of: repoRoot.path + "/", with: "")
            let text = try String(contentsOf: url, encoding: .utf8)
            guard text.contains("NSBackgroundActivityScheduler") else { continue }
            if !allowlist.contains(rel) {
                violations.append(rel)
            }
        }
        XCTAssertTrue(violations.isEmpty, "NSBackgroundActivityScheduler outside allowlist: \(violations)")
    }

    func testProfileRepositorySyncNoOpStubsAbsent() throws {
        let collegeDir = repoRoot.appendingPathComponent("College")
        let enumerator = FileManager.default.enumerator(
            at: collegeDir,
            includingPropertiesForKeys: nil
        )!
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            guard name.hasPrefix("ProfileRepository+"), name.contains("Sync") else { continue }
            if name == "ProfileRepository+PlannerSync.swift" { continue }
            XCTFail("ProfileRepository+*Sync stub reappeared: \(name)")
        }
    }

    func testBackgroundServiceSchedulerInvokesCompletion() throws {
        let source = try String(
            contentsOf: repoRoot.appendingPathComponent(
                "College/Core/Platform/Services/BackgroundServiceScheduler.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("completionGate.finish(.finished)"))
        XCTAssertTrue(source.contains("CompletionOnce"))
    }

    func testDeprecatedLifecycleShimsExist() throws {
        let source = try String(
            contentsOf: repoRoot.appendingPathComponent(
                "College/Core/Platform/Services/BackgroundServiceDeprecatedShims.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("startTrackedServiceTask"))
        XCTAssertTrue(source.contains("makeBackgroundActivityScheduler"))
        XCTAssertTrue(source.contains("deprecated"))
    }

    func testXcodebuildTestParallelismCappedAtTwo() throws {
        let flags = try String(
            contentsOf: repoRoot.appendingPathComponent("scripts/xcodebuild-test-parallel-flags.sh"),
            encoding: .utf8
        )
        XCTAssertTrue(flags.contains("XCODEBUILD_TEST_MAX_PARALLEL_WORKERS=\"${XCODEBUILD_TEST_MAX_PARALLEL_WORKERS:-2}\""))
        XCTAssertTrue(flags.contains("-maximum-parallel-testing-workers"))
    }

    func testJobOpeningsViewDoesNotStartJobBoardCoordinatorDirectly() throws {
        let source = try String(
            contentsOf: repoRoot.appendingPathComponent(
                "College/Features/Career/Job Board/Views/JobOpeningsView.swift"
            ),
            encoding: .utf8
        )
        XCTAssertFalse(
            source.contains("jobBoardCoordinator.start()"),
            "Job board sync must start via BackgroundServiceRegistry scene activation"
        )
    }

    func testCloudIntegrationServiceDoesNotAutoRescanInInit() throws {
        let source = try String(
            contentsOf: repoRoot.appendingPathComponent(
                "College/Core/Services/CloudIntegrationService.swift"
            ),
            encoding: .utf8
        )
        let initBody = source.components(separatedBy: "private init()").dropFirst().first ?? ""
        XCTAssertFalse(
            initBody.contains("startAutoRescan()"),
            "Cloud rescan must start via cloud_integration_rescan manifest entry"
        )
    }
}
