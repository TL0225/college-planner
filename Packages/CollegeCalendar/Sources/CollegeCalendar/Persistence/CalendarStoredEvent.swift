import Foundation

/// App-agnostic calendar event snapshot for sync, export, and UI (ADR 004 Layer 2–3 bridge).
public struct CalendarStoredEvent: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let notes: String?
    public let location: String?
    public let startDate: Date
    public let endDate: Date
    public let allDay: Bool
    public let providerSource: String?
    public let customColorHex: String?
    public let recurrenceRule: String?
    public let providerEventId: String?
    public let attendeesJSON: String?
    public let courseID: UUID?
    public let courseCode: String?
    public let semesterID: UUID?

    public init(
        id: UUID,
        title: String,
        notes: String? = nil,
        location: String? = nil,
        startDate: Date,
        endDate: Date,
        allDay: Bool,
        providerSource: String? = nil,
        customColorHex: String? = nil,
        recurrenceRule: String? = nil,
        providerEventId: String? = nil,
        attendeesJSON: String? = nil,
        courseID: UUID? = nil,
        courseCode: String? = nil,
        semesterID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.location = location
        self.startDate = startDate
        self.endDate = endDate
        self.allDay = allDay
        self.providerSource = providerSource
        self.customColorHex = customColorHex
        self.recurrenceRule = recurrenceRule
        self.providerEventId = providerEventId
        self.attendeesJSON = attendeesJSON
        self.courseID = courseID
        self.courseCode = courseCode
        self.semesterID = semesterID
    }
}

public struct CalendarSemesterRecord: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

public struct CalendarPlannerTaskRecord: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let dueDate: Date?

    public init(id: UUID, title: String, dueDate: Date?) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
    }
}
