// CalendarEditorSession.swift
// Feature: Calendar
// Purpose: Manages draft calendar events for live grid preview while the editor is open.

import CollegePlatform
import Combine
import Foundation

/// Manages draft calendar events for live grid preview while the editor is open.
@MainActor
public final class CalendarEditorSession: ObservableObject {
    @Published public private(set) var draftEventID: UUID?

    public init() {}

    public func createDraft(
        title: String,
        start: Date,
        end: Date,
        allDay: Bool,
        semesterID: UUID? = nil,
        persistence: (any CalendarPersistencePort)? = CalendarPersistenceAccess.persistence
    ) throws -> UUID {
        guard let persistence else { throw CalendarEditorSessionError.persistenceUnavailable }
        discardDraft(persistence: persistence)
        let id = persistence.addCalendarEvent(
            title: title.isEmpty ? "New Event" : title,
            startDate: start,
            endDate: end,
            allDay: allDay,
            semesterID: semesterID,
            notes: nil,
            location: nil
        )
        draftEventID = id
        notifyGrid(persistence: persistence)
        return id
    }

    public func discardDraft(persistence: (any CalendarPersistencePort)? = CalendarPersistenceAccess.persistence) {
        guard let persistence, let id = draftEventID else { return }
        persistence.deleteCalendarEvent(id: id)
        draftEventID = nil
        notifyGrid(persistence: persistence)
    }

    public func clearDraftTracking(keeping eventID: UUID) {
        if draftEventID == eventID {
            draftEventID = nil
        }
    }

    private func notifyGrid(persistence: any CalendarPersistencePort) {
        persistence.notifyCalendarDidChange()
        NotificationCenter.default.post(
            name: .calendarDidChange,
            object: nil,
            userInfo: ["message": CalendarDidChangeMessage(reason: .userEdit, eventIDs: [])]
        )
    }
}

public enum CalendarEditorSessionError: Error {
    case persistenceUnavailable
}
