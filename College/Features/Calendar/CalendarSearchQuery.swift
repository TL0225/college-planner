// CalendarSearchQuery.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarSearchQuery.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// Background-safe calendar search (Phase 3 P0 — avoids blocking main `ModelContext`).
enum CalendarSearchQuery {
    static func searchEvents(
        query: String,
        semesterID: UUID?,
        limit: Int,
        context: ModelContext
    ) throws -> [CalendarEvent] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let effectiveLimit = min(max(limit, 1), 100)
        let scanLimit = min(effectiveLimit * 8, 400)

        var descriptor = FetchDescriptor<CalendarEvent>(
            sortBy: [
                SortDescriptor(\.startDate, order: .forward),
                SortDescriptor(\.title, order: .forward),
            ]
        )
        descriptor.fetchLimit = scanLimit
        let candidates = try context.fetch(descriptor)

        return candidates.filter { event in
            if let semesterID {
                if let linked = event.semester?.id, linked != semesterID { return false }
            }
            return matchesSearchQuery(trimmed, event: event)
        }
        .prefix(effectiveLimit)
        .map { $0 }
    }

    private static func matchesSearchQuery(_ query: String, event: CalendarEvent) -> Bool {
        if event.title.localizedStandardContains(query) { return true }
        if let notes = event.notes, notes.localizedStandardContains(query) { return true }
        if let location = event.location, location.localizedStandardContains(query) { return true }
        if let code = event.course?.code, code.localizedStandardContains(query) { return true }
        if let name = event.course?.name, name.localizedStandardContains(query) { return true }
        return false
    }
}
