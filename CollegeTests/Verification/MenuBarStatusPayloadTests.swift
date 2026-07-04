// MenuBarStatusPayloadTests.swift
// Snow Leopard V&V: malformed catalog progress payloads are safe no-ops (Q5).

import XCTest
@testable import College

@MainActor
final class MenuBarStatusPayloadTests: XCTestCase {
    override func setUp() {
        super.setUp()
        CollegeMenuBarStatusModel.shared.resetForTesting()
        CollegeMenuBarStatusModel.shared.startObservingProgressNotifications()
    }

    func testMalformedImportNotificationDoesNotTrap() {
        let model = CollegeMenuBarStatusModel.shared
        NotificationCenter.default.post(
            name: .collegeCatalogBackgroundImportProgress,
            object: nil,
            userInfo: ["fraction": "not-a-double", "title": 42]
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        switch model.catalog {
        case .idle, .inProgress:
            break
        default:
            XCTFail("Unexpected terminal state from malformed payload")
        }
    }

    func testValidImportProgressUpdatesState() {
        let model = CollegeMenuBarStatusModel.shared
        NotificationCenter.default.post(
            name: .collegeCatalogBackgroundImportProgress,
            object: nil,
            userInfo: ["title": "Importing", "fraction": 0.5]
        )
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        if case .inProgress(let title, let fraction, _) = model.catalog {
            XCTAssertTrue(title.contains("Importing"))
            XCTAssertEqual(fraction, 0.5)
        } else {
            XCTFail("Expected in-progress state")
        }
    }
}
