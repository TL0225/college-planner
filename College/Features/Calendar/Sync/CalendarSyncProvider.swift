// CalendarSyncProvider.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarSyncProviderID.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Provider identifier for sync map namespaces and routing.
enum CalendarSyncProviderID: String, Sendable, CaseIterable {
    case apple
    case google
    case outlook
    case icloud
}

/// Protocol-oriented calendar sync surface. Implementations are `actor` types (Phase 2a+).
protocol CalendarSyncProvider: Actor {
    var id: CalendarSyncProviderID { get }

    func connect() async throws
    func disconnect() async
    func sync(showNotifications: Bool) async
    func exportEvent(eventID: UUID) async throws
    func deleteRemoteEvent(localEventID: UUID) async throws
}

@MainActor
enum CalendarSyncEventResolver {
    static func calendarEvent(for eventID: UUID) -> CalendarEvent? {
        try? AppDataStore.shared.calendarRepository.fetchCalendarEvent(id: eventID)
    }
}

/// Shared sync completion hook — Phase 4 implements reminder batch scheduling.
enum CalendarSyncCompletionHooks {
    @MainActor
    static func onSyncCompleted(importedEventIDs: [UUID]) {
        guard !importedEventIDs.isEmpty else { return }
        let repo = AppDataStore.shared.calendarRepository
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
