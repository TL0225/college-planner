// PlannerChunkProjectionCalendarTests.swift
import Foundation
import SwiftData
import Testing
@testable import College

@Suite("Planner Chunk Projection Calendar")
struct PlannerChunkProjectionCalendarTests {

    @Test("Calendar event chunk includes enrichment fields")
    @MainActor
    func calendarEventChunkIncludesEnrichmentFields() {
        let event = CalendarEvent(
            title: "CSE411 Lecture",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600)
        )
        event.location = "Engineering 123"
        event.notes = "Midterm review"
        event.attendeesJSON = #"["alice@example.com"]"#

        let chunks = PlannerChunkProjection.chunks(from: event)
        #expect(!chunks.isEmpty)
        let body = chunks[0].ftsBody
        #expect(body.contains("CSE411"))
        #expect(body.contains("Engineering 123"))
        #expect(body.contains("Midterm review"))
        #expect(body.contains("alice@example.com"))
    }
}
