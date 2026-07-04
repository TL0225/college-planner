// CareerWorkspaceCompileSmokeTests.swift
// Feature: Career
// Purpose: Minimal compile/link smoke for Career workspace key types.

import CollegeCareer
import SwiftUI
import XCTest
@testable import College

@MainActor
final class CareerWorkspaceCompileSmokeTests: XCTestCase {
    func testCareerSceneState_defaultsAndProjection() {
        let scene = CareerSceneState()
        XCTAssertEqual(scene.selectedView, .board)
        XCTAssertEqual(scene.boardLayout, .kanban)
        let projection = scene.toolbarProjection
        XCTAssertEqual(projection.selectedView, .board)
        XCTAssertEqual(projection.boardLayout, .kanban)
    }

    func testCareerKeyTypes_compileAndLink() {
        XCTAssertTrue(CareerWorkspaceView.self == CareerWorkspaceView.self)
        XCTAssertTrue(CareerApplicationFormSheet.self == CareerApplicationFormSheet.self)
        XCTAssertTrue(CareerStatsView.self == CareerStatsView.self)
        XCTAssertTrue(ResumeManagerView.self == ResumeManagerView.self)
        XCTAssertEqual(CareerResumeMetadataV1.Kind.general.rawValue, "general")
        XCTAssertNotNil(CareerResumeHashing.hash(normalizedPlainText: "smoke"))
        XCTAssertNotNil(CareerATSAdviceValidator.validatedTip("Mention Swift — it appears in the JD."))
    }

    func testCareerSubView_allCasesReachable() {
        for subview in CareerSubView.allCases {
            let scene = CareerSceneState()
            scene.select(subview)
            XCTAssertEqual(scene.selectedView, subview)
        }
    }
}
