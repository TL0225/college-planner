// CareerReadBridgeTests.swift
// Feature: Career
// Purpose: Career module — CareerReadBridgeTests.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import XCTest
@testable import College

@MainActor
final class CareerReadBridgeTests: PersistenceTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        let ctx = AppDataStore.shared.profileContext
        for app in try ctx.fetch(FetchDescriptor<JobApplication>()) {
            ctx.delete(app)
        }
        try ctx.save()
    }

    func testPipelineMetricsFromStore() throws {
        let repo = CareerRepository(context: profileContext)
        _ = try repo.addApplication(
            title: "Engineer",
            company: "Acme",
            postingURLString: "",
            jobDescriptionText: "",
            interviewStatus: "",
            applicationDeadline: nil,
            status: .applied
        )
        try profileContext.save()

        let metrics = CareerReadBridge.pipelineMetrics()
        XCTAssertEqual(metrics.totalApplied, 1)
    }

    func testApplicationStatsRowsFromStore() throws {
        let repo = CareerRepository(context: profileContext)
        _ = try repo.addApplication(
            title: "Engineer",
            company: "Acme",
            postingURLString: "",
            jobDescriptionText: "",
            interviewStatus: "",
            applicationDeadline: nil,
            status: .applied
        )
        try profileContext.save()

        let rows = CareerReadBridge.applicationStatsRows()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.company, "Acme")
    }

    func testCareerApplicationsFromStore() throws {
        let repo = CareerRepository(context: profileContext)
        _ = try repo.addApplication(
            title: "Engineer",
            company: "Acme",
            postingURLString: "",
            jobDescriptionText: "",
            interviewStatus: "",
            applicationDeadline: nil,
            status: .applied
        )
        try profileContext.save()

        let apps = CareerReadBridge.careerApplications()
        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(apps.first?.company, "Acme")
    }
}
