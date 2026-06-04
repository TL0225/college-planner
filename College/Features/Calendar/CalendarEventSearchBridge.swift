// CalendarEventSearchBridge.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarEventSearchHit.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// Normalized calendar search row (local store).
struct CalendarEventSearchHit: Equatable, Sendable {
    let id: UUID
    let title: String
    let startDate: Date
    let endDate: Date?
    let location: String?
    let notes: String?
}

@MainActor
enum CalendarEventSearchBridge {
    static func search(
        query: String,
        semester: PlannerSemester? = nil,
        limit: Int = 50,
        collegePersistence: CollegePersistence = .shared
    ) -> [CalendarEventSearchHit] {
        _ = collegePersistence
        return searchViaStore(
            query: query,
            semesterID: semester?.id,
            limit: limit
        ) ?? []
    }

    /// Runs search on a background `ModelContext` (Phase 3 P0).
    static func searchOffMain(
        query: String,
        semester: PlannerSemester? = nil,
        limit: Int = 50
    ) async -> [CalendarEventSearchHit] {
        let container = await MainActor.run { AppDataStore.shared.profileContainer }
        let semesterID = semester?.id
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            guard let events = try? CalendarSearchQuery.searchEvents(
                query: trimmed,
                semesterID: semesterID,
                limit: limit,
                context: context
            ) else {
                return [CalendarEventSearchHit]()
            }
            return events.map {
                CalendarEventSearchHit(
                    id: $0.id,
                    title: $0.title,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    location: $0.location,
                    notes: $0.notes
                )
            }
        }.value
    }

    static func resolveEvent(
        id: UUID,
        collegePersistence: CollegePersistence = .shared
    ) -> CalendarEvent? {
        collegePersistence.calendarEventEntity(id: id)
    }

    private static func searchViaStore(
        query: String,
        semesterID: UUID?,
        limit: Int
    ) -> [CalendarEventSearchHit]? {
        let repo = CalendarRepository(context: AppDataStore.shared.profileContext)
        guard let events = try? repo.searchEvents(
            query: query,
            semesterID: semesterID,
            limit: limit
        ) else {
            return nil
        }
        return events.map {
            CalendarEventSearchHit(
                id: $0.id,
                title: $0.title,
                startDate: $0.startDate,
                endDate: $0.endDate,
                location: $0.location,
                notes: $0.notes
            )
        }
    }
}
