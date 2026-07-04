// CalendarEventWritePipelineIntegrationTests.swift
// Integration tests for calendar event write pipeline create/update/delete and export health.

import CollegeCalendar
import SwiftData
import XCTest
@testable import College

@MainActor
final class CalendarEventWritePipelineIntegrationTests: PersistenceTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        CalendarPersistencePortBootstrap.wire()
        CalendarIntegrationBridge.manager = nil
    }

    func testPipelineCreateUpdateDeletePreservesSingleRow() async throws {
        let pipeline = CalendarEventWritePipeline.shared
        let start = Date(timeIntervalSince1970: 1_740_000_000)
        let end = start.addingTimeInterval(3600)
        let input = CalendarEventWriteInput(
            title: "Pipeline Lecture",
            startDate: start,
            endDate: end,
            allDay: false,
            notes: "v1"
        )
        let options = CalendarEventWriteOptions(skipExport: true, skipReminders: true)

        let eventID = try await pipeline.create(input: input, options: options)

        let movedStart = start.addingTimeInterval(86_400)
        let movedEnd = movedStart.addingTimeInterval(3600)
        var updated = input
        updated.startDate = movedStart
        updated.endDate = movedEnd
        updated.notes = "v2"
        try await pipeline.update(eventID: eventID, input: updated, options: options)

        let events = try profileContext.fetch(FetchDescriptor<CalendarEvent>())
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.id, eventID)
        XCTAssertEqual(events.first?.startDate, movedStart)
        XCTAssertEqual(events.first?.notes, "v2")

        try await pipeline.delete(eventID: eventID)
        ModelMergeCoalescer.flushNow()
        XCTAssertNil(try CalendarRepository(context: profileContext).fetchCalendarEvent(id: eventID))
    }

    func testExportAfterWriteReturnsFalseWhenManagerMissing() async throws {
        let pipeline = CalendarEventWritePipeline.shared
        let start = Date(timeIntervalSince1970: 1_740_000_000)
        let eventID = try await pipeline.create(
            input: CalendarEventWriteInput(
                title: "Export Probe",
                startDate: start,
                endDate: start.addingTimeInterval(3600),
                allDay: false
            ),
            options: CalendarEventWriteOptions(skipExport: true, skipReminders: true)
        )

        let exportResult = await pipeline.exportAfterWriteAndReport(eventID: eventID)
        XCTAssertFalse(exportResult.allSucceeded)
        XCTAssertFalse(exportResult.google ?? true)
    }
}
