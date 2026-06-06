// CalendarEditorSession.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarEditorSession.
// Data: CollegePersistence / repositories when applicable.

import CollegePlatform
import Combine
import Foundation

/// Manages draft calendar events for live grid preview while the editor is open.
@MainActor
final class CalendarEditorSession: ObservableObject {
    @Published private(set) var draftEventID: UUID?

    func createDraft(
        title: String,
        start: Date,
        end: Date,
        allDay: Bool,
        semester: PlannerSemester? = nil,
        collegePersistence: CollegePersistence = .shared
    ) throws -> UUID {
        discardDraft(collegePersistence: collegePersistence)
        let id = collegePersistence.addCalendarEvent(
            title: title.isEmpty ? "New Event" : title,
            startDate: start,
            endDate: end,
            allDay: allDay,
            semester: semester
        )
        draftEventID = id
        notifyGrid(collegePersistence: collegePersistence)
        return id
    }

    func discardDraft(collegePersistence: CollegePersistence = .shared) {
        guard let id = draftEventID else { return }
        collegePersistence.deleteCalendarEvent(id: id)
        draftEventID = nil
        notifyGrid(collegePersistence: collegePersistence)
    }

    func clearDraftTracking(keeping eventID: UUID) {
        if draftEventID == eventID {
            draftEventID = nil
        }
    }

    private func notifyGrid(collegePersistence: CollegePersistence) {
        collegePersistence.notifyCalendarDidChange()
        NotificationCenter.default.post(
            name: .calendarDidChange,
            object: nil,
            userInfo: ["message": CalendarDidChangeMessage(reason: .userEdit, eventIDs: [])]
        )
    }
}
