// PlannerMemoryQuery.swift
// Feature: Core
// Purpose: Core module — Hit.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// Phase 7: lightweight planner memory search over indexed calendar chunks (local store-only).
enum PlannerMemoryQuery {
    struct Hit: Sendable {
        var title: String
        var snippet: String
        var referenceDate: Date?
    }

    @MainActor
    static func searchEvents(matching query: String, limit: Int = 12) -> [Hit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }

        let repo = CollegePersistence.shared.calendarRepository
        let start = Calendar.current.date(byAdding: .year, value: -2, to: Date()) ?? Date()
        let end = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        guard let events = try? repo.fetchEventsOverlapping(start: start, end: end, limit: 200) else {
            return []
        }

        var hits: [Hit] = []
        for event in events.sorted(by: { $0.startDate > $1.startDate }) {
            let chunks = PlannerChunkProjection.chunks(from: event)
            for chunk in chunks where chunk.ftsBody.lowercased().contains(needle) {
                hits.append(
                    Hit(
                        title: event.title.isEmpty ? "Event" : event.title,
                        snippet: chunk.ftsBody,
                        referenceDate: event.startDate
                    )
                )
                if hits.count >= limit { return hits }
            }
        }
        return hits
    }
}
