// CareerSyncBridgeTests.swift
// Feature: Career
// Purpose: Career module — CareerSyncBridgeTests.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import XCTest
@testable import College

@MainActor
final class CareerSyncBridgeTests: PersistenceTestCase {
    func testCareerApplicationAndEventWrites() throws {
        let careerRepo = CareerRepository(context: profileContext)
        let application = try careerRepo.addApplication(
            title: "Software Engineer",
            company: "Acme Corp",
            postingURLString: "https://example.com/jobs/1",
            jobDescriptionText: "Build things",
            interviewStatus: "",
            applicationDeadline: nil,
            status: .applied
        )

        let event = CareerEvent(completed: false)
        event.kindRaw = "followup"
        event.title = "Send thank-you"
        event.date = Date()
        event.application = application
        profileContext.insert(event)
        try profileContext.save()

        XCTAssertEqual(try careerRepo.fetchApplications(limit: 10).count, 1)
        XCTAssertEqual(try careerRepo.fetchApplications(limit: 10).first?.title, "Software Engineer")
        XCTAssertEqual(try careerRepo.fetchUpcomingEvents(limit: 10).count, 1)
    }

    func testDeleteApplicationRemovesStoreRow() throws {
        let careerRepo = CareerRepository(context: profileContext)
        let application = try careerRepo.addApplication(
            title: "Temporary Role",
            company: "TempCo",
            postingURLString: "",
            jobDescriptionText: "",
            interviewStatus: "",
            applicationDeadline: nil,
            status: .interested
        )
        XCTAssertEqual(try careerRepo.fetchApplications(limit: 5).count, 1)

        try careerRepo.deleteApplication(application)
        XCTAssertTrue(try careerRepo.fetchApplications(limit: 5).isEmpty)
    }

    func testPipelineMetricsFromApplications() throws {
        let careerRepo = CareerRepository(context: profileContext)
        _ = try careerRepo.addApplication(
            title: "Engineer",
            company: "A",
            postingURLString: "",
            jobDescriptionText: "",
            interviewStatus: "",
            applicationDeadline: nil,
            status: .applied
        )
        _ = try careerRepo.addApplication(
            title: "Engineer II",
            company: "B",
            postingURLString: "",
            jobDescriptionText: "",
            interviewStatus: "",
            applicationDeadline: nil,
            status: .interviewing
        )
        _ = try careerRepo.addApplication(
            title: "Staff",
            company: "C",
            postingURLString: "",
            jobDescriptionText: "",
            interviewStatus: "",
            applicationDeadline: nil,
            status: .offer
        )

        let metrics = try careerRepo.pipelineMetrics()
        XCTAssertEqual(metrics.totalApplied, 3)
        XCTAssertEqual(metrics.interviews, 2)
        XCTAssertEqual(metrics.offers, 1)
    }
}
