// BackgroundServiceComplianceTests.swift
// Architecture gate: manifest integrity and tier coverage.

import XCTest
@testable import College

final class BackgroundServiceComplianceTests: XCTestCase {
    func testManifestIDsAreNonEmptyAndUnique() {
        let ids = BackgroundServiceManifest.allIDs
        XCTAssertFalse(ids.isEmpty)
        XCTAssertEqual(ids.count, Set(ids).count, "Duplicate manifest ids: \(ids)")
    }

    func testManifestDescriptorCountAtLeast60() {
        XCTAssertGreaterThanOrEqual(
            BackgroundServiceManifest.allDescriptors().count,
            60,
            "Manifest descriptor count regressed"
        )
    }

    func testTier1DescriptorsHaveMetadata() {
        let tier1 = BackgroundServiceManifest.allDescriptors().filter {
            switch $0.activation {
            case .onDemand:
                return false
            default:
                return true
            }
        }
        XCTAssertFalse(tier1.isEmpty)
        for descriptor in tier1 {
            XCTAssertFalse(descriptor.id.isEmpty)
            XCTAssertFalse(descriptor.displayName.isEmpty)
        }
    }

    func testLongLivedServicesWireExplicitStopHandlers() {
        let manifestSource = try! String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("College/Core/Platform/Services/BackgroundServiceManifest.swift"),
            encoding: .utf8
        )
        let requiredStopPatterns: [(id: String, pattern: String)] = [
            ("cloud_integration_rescan", "stopAutoRescan"),
            ("ics_subscription_refresh", "ICSSubscriptionRefreshService.shared.stop"),
            ("academic_calendar_refresh", "AcademicCalendarRefreshService.shared.stop"),
            ("calendar_provider_sync", "stopProviderBackgroundSyncLoops"),
            ("fs_watchdog", "stopWatching"),
            ("session_termination", "markCleanTermination"),
        ]
        for entry in requiredStopPatterns {
            XCTAssertTrue(
                manifestSource.contains("id: \"\(entry.id)\""),
                "Missing manifest entry for \(entry.id)"
            )
            let entrySlice = manifestSource.range(
                of: "id: \"\(entry.id)\"",
                options: [],
                range: manifestSource.startIndex..<manifestSource.endIndex
            )
            XCTAssertNotNil(entrySlice, "Could not locate \(entry.id) block")
            if let entrySlice {
                let blockEnd = manifestSource[entrySlice.lowerBound...].prefix(800)
                XCTAssertTrue(
                    blockEnd.contains(entry.pattern),
                    "\(entry.id) stop handler should reference \(entry.pattern)"
                )
            }
        }
    }

    func testSchedulerIDsAreStableStrings() {
        XCTAssertFalse(BackgroundServiceSchedulerIDs.academicCalendarRefresh.isEmpty)
        XCTAssertTrue(BackgroundServiceSchedulerIDs.academicCalendarRefresh.hasPrefix("com.college."))
        XCTAssertTrue(BackgroundServiceSchedulerIDs.calendarGoogleProviderSync.hasPrefix("com.college."))
        XCTAssertTrue(BackgroundServiceSchedulerIDs.calendarOutlookProviderSync.hasPrefix("com.college."))
        XCTAssertTrue(BackgroundServiceSchedulerIDs.calendarICloudProviderSync.hasPrefix("com.college."))
    }

    func testTelemetryServiceKeysAlignWithManifestOrAllowlist() throws {
        let manifestIDs = Set(BackgroundServiceManifest.allIDs)
        let allowedNonManifestKeys: Set<String> = ["app"]
        let collegeDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("College")

        let pattern = #"markServiceState\("([^"]+)""#
        let regex = try NSRegularExpression(pattern: pattern)
        let enumerator = FileManager.default.enumerator(
            at: collegeDir,
            includingPropertiesForKeys: nil
        )!
        var literals: Set<String> = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            regex.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match, match.numberOfRanges > 1,
                      let keyRange = Range(match.range(at: 1), in: text) else { return }
                literals.insert(String(text[keyRange]))
            }
        }

        XCTAssertFalse(literals.isEmpty, "Expected markServiceState literals in College sources")
        let unexpected = literals.subtracting(manifestIDs).subtracting(allowedNonManifestKeys)
        XCTAssertTrue(
            unexpected.isEmpty,
            "markServiceState keys must match manifest ids or allowlist; unexpected: \(unexpected.sorted())"
        )
    }
}
