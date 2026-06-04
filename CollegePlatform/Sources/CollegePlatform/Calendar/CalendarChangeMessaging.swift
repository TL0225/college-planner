import Foundation

public enum CalendarChangeReason: Sendable {
    case userEdit
    case syncImport
    case migration
    case delete
}

public struct CalendarDidChangeMessage: Sendable {
    public var reason: CalendarChangeReason
    public var eventIDs: [UUID]

    public init(reason: CalendarChangeReason, eventIDs: [UUID] = []) {
        self.reason = reason
        self.eventIDs = eventIDs
    }
}

public extension Notification.Name {
    static let calendarDidChange = Notification.Name("College.CalendarDidChange")
    static let calendarEditorSave = Notification.Name("CalendarEditorSave")
    static let calendarEditorDismiss = Notification.Name("CalendarEditorDismiss")
}
