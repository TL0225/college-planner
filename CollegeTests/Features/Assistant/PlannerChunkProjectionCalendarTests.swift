// PlannerChunkProjectionCalendarTests.swift
// Feature: Assistant
// Purpose: Assistant module — PlannerChunkProjectionCalendarTests.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import XCTest
@testable import College

/// Phase 2c acceptance: calendar events index notes, guests, course, location.
@MainActor
final class PlannerChunkProjectionCalendarTests: PersistenceTestCase {
    func testCalendarEventChunk_includesEnrichmentFields() throws {
        let event = CalendarEvent(
            title: "CSE411 Lecture",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600)
        )
        event.location = "Engineering 123"
        event.notes = "Midterm review"
        event.attendeesJSON = #"["alice@example.com"]"#

        let chunks = PlannerChunkProjection.chunks(from: event)
        XCTAssertFalse(chunks.isEmpty)
        let body = chunks[0].ftsBody
        XCTAssertTrue(body.contains("CSE411"))
        XCTAssertTrue(body.contains("Engineering 123"))
        XCTAssertTrue(body.contains("Midterm review"))
        XCTAssertTrue(body.contains("alice@example.com"))
    }
}
