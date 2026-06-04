// CalendarEditorAnchor.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarEditorAnchor.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Identifies a grid-attached calendar editor popover (Liquid Glass `popover(item:)`).
struct CalendarEditorAnchor: Identifiable {
    enum Mode {
        case add(semesterID: UUID?, title: String?, start: Date, end: Date, allDay: Bool = false)
        case edit(eventID: UUID)
        case monthAllDayChoice(date: Date)
    }

    let id = UUID()
    var attachment: PopoverAttachmentAnchor
    var arrowEdge: Edge
    var mode: Mode

    static func addFromGrid(
        start: Date,
        end: Date,
        semesterID: UUID? = nil,
        title: String? = nil,
        allDay: Bool = false,
        arrowEdge: Edge = .leading
    ) -> CalendarEditorAnchor {
        CalendarEditorAnchor(
            attachment: .rect(.bounds),
            arrowEdge: arrowEdge,
            mode: .add(semesterID: semesterID, title: title, start: start, end: end, allDay: allDay)
        )
    }

    static func edit(
        eventID: UUID,
        arrowEdge: Edge = .trailing
    ) -> CalendarEditorAnchor {
        CalendarEditorAnchor(
            attachment: .rect(.bounds),
            arrowEdge: arrowEdge,
            mode: .edit(eventID: eventID)
        )
    }
}
