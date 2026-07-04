import Foundation
import Observation

public extension Notification.Name {
    /// Posted when calendar events are created, updated, or deleted.
    static let calendarDidChange = Notification.Name("com.timothy.college.calendarDidChange")
    static let calendarEditorSave = Notification.Name("CalendarEditorSave")
    static let calendarEditorDismiss = Notification.Name("CalendarEditorDismiss")
}

public enum CalendarChangeReason: String, Sendable, Codable {
    case userEdit
    case syncImport
    case syncExport
    case bulkDelete
    case systemRepair
    case delete
    case migration
}

public struct CalendarDidChangeMessage: Sendable, Codable, Equatable {
    public var reason: CalendarChangeReason
    public var eventIDs: [UUID]

    public init(reason: CalendarChangeReason, eventIDs: [UUID]) {
        self.reason = reason
        self.eventIDs = eventIDs
    }
}

/// Lightweight token publisher for calendar invalidation without NotificationCenter in tests.
@MainActor
@Observable
public final class CalendarChangePublisher {
    public static let shared = CalendarChangePublisher()

    public private(set) var revision: Int = 0
    /// Alias used by `CollegeCalendar` write pipeline.
    public var generationToken: Int { revision }

    public init() {}

    public func bump() {
        revision &+= 1
    }
}
