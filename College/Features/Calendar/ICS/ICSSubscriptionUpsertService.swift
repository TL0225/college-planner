// ICSSubscriptionUpsertService.swift
// Feature: Calendar
// Purpose: Calendar module — ICSSubscriptionUpsertService.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

enum ICSSubscriptionUpsertService {
    @MainActor
    static func upsert(
        events: [ICSCalendarParser.ParsedEvent],
        subscriptionID: UUID,
        sourceURL: String
    ) async {
        let repo = AppDataStore.shared.calendarRepository
        let trimmedURL = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let providerSource = "ics:\(trimmedURL)"

        for parsed in events {
            let uid = parsed.uid.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !uid.isEmpty else { continue }

            let overlapping = (try? repo.fetchEventsOverlapping(
                start: parsed.start.addingTimeInterval(-1),
                end: parsed.end.addingTimeInterval(1),
                limit: 5
            )) ?? []
            if let existing = overlapping.first(where: { ($0.providerEventId ?? "") == uid }) {
                _ = existing
                continue
            }

            if let event = try? repo.createCalendarEvent(
                title: parsed.title,
                startDate: parsed.start,
                endDate: parsed.end,
                allDay: parsed.allDay,
                notes: parsed.notes,
                location: parsed.location,
                providerSource: providerSource
            ) {
                event.providerEventId = uid
            }
        }

        _ = try? AppDataStore.shared.profileSave()
        CollegePersistence.shared.notifyCalendarDidChange()
    }
}
