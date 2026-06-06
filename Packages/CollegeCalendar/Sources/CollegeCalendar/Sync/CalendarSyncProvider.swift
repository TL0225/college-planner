// CalendarSyncProvider.swift
// Feature: Calendar
// Purpose: Protocol-oriented calendar sync surface.

import Foundation

/// Provider identifier for sync map namespaces and routing.
public enum CalendarSyncProviderID: String, Sendable, CaseIterable {
    case apple
    case google
    case outlook
    case icloud
}

/// Protocol-oriented calendar sync surface. Implementations are `actor` types (Phase 2a+).
public protocol CalendarSyncProvider: Actor {
    var id: CalendarSyncProviderID { get }

    func connect() async throws
    func disconnect() async
    func sync(showNotifications: Bool) async
    func exportEvent(eventID: UUID) async throws
    func deleteRemoteEvent(localEventID: UUID) async throws
}

@MainActor
public enum CalendarSyncEventResolver {
    public static func calendarEvent(for eventID: UUID) -> CalendarStoredEvent? {
        try? CalendarPersistenceAccess.writeRepository?.fetchCalendarEvent(id: eventID)
    }
}

/// Shared sync completion hook — schedules reminders after provider import.
public enum CalendarSyncCompletionHooks {
    @MainActor
    public static func onSyncCompleted(importedEventIDs: [UUID]) {
        guard !importedEventIDs.isEmpty, let repo = CalendarPersistenceAccess.writeRepository else { return }
        var infos: [CalendarReminderInfo] = []
        for id in importedEventIDs {
            guard let event = try? repo.fetchCalendarEvent(id: id) else { continue }
            infos.append(
                CalendarReminderInfo(
                    eventID: id,
                    title: event.title,
                    startDate: event.startDate,
                    leadMinutes: nil,
                    conferenceURL: nil
                )
            )
        }
        CalendarReminderScheduler.shared.scheduleBatch(events: infos)
    }
}

public enum CalendarSyncProviderError: Error {
    case missingEvent
}
