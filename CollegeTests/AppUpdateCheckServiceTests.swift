import XCTest
@testable import College

final class AppUpdateCheckServiceTests: XCTestCase {
    func testVersionComparisonHandlesNewerPatchMinorAndMajorVersions() {
        XCTAssertTrue(AppUpdateCheckService.isVersion("1.0.1", newerThan: "1.0.0"))
        XCTAssertTrue(AppUpdateCheckService.isVersion("1.1.0", newerThan: "1.0.9"))
        XCTAssertTrue(AppUpdateCheckService.isVersion("2.0.0", newerThan: "1.9.9"))
    }

    func testVersionComparisonHandlesVPrefixedTags() {
        XCTAssertTrue(AppUpdateCheckService.isVersion("v1.2.0", newerThan: "1.1.9"))
        XCTAssertTrue(AppUpdateCheckService.isVersion("V1.2.0", newerThan: "1.1.9"))
    }

    func testVersionComparisonDoesNotTreatEqualOrOlderVersionsAsUpdates() {
        XCTAssertFalse(AppUpdateCheckService.isVersion("1.2.0", newerThan: "1.2.0"))
        XCTAssertFalse(AppUpdateCheckService.isVersion("1.2", newerThan: "1.2.0"))
        XCTAssertFalse(AppUpdateCheckService.isVersion("1.1.9", newerThan: "1.2.0"))
    }

    func testUpdateInfoReportsAvailabilityFromVersionComparison() throws {
        let releaseURL = try XCTUnwrap(URL(string: "https://github.com/TL0225/college-planner/releases/tag/v1.1.0"))
        let downloadURL = try XCTUnwrap(URL(string: "https://github.com/TL0225/college-planner/releases/download/v1.1.0/College.zip"))

        let info = AppUpdateInfo(
            currentVersion: "1.0.0",
            latestVersion: "1.1.0",
            releasePageURL: releaseURL,
            downloadURL: downloadURL,
            releaseName: "College 1.1.0"
        )

        XCTAssertTrue(info.isUpdateAvailable)
    }
}
