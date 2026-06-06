import SwiftUI

/// Identifies a grid-attached calendar editor popover (Liquid Glass `popover(item:)`).
public struct CalendarEditorAnchor: Identifiable {
    public enum Mode {
        case add(semesterID: UUID?, title: String?, start: Date, end: Date, allDay: Bool = false)
        case edit(eventID: UUID)
        case monthAllDayChoice(date: Date)
    }

    public let id = UUID()
    public var attachment: PopoverAttachmentAnchor
    public var arrowEdge: Edge
    public var mode: Mode

    public init(attachment: PopoverAttachmentAnchor, arrowEdge: Edge, mode: Mode) {
        self.attachment = attachment
        self.arrowEdge = arrowEdge
        self.mode = mode
    }

    public static func addFromGrid(
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

    public static func edit(
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
