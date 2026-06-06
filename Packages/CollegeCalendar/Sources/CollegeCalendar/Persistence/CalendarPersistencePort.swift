import Foundation

/// Calendar-facing persistence surface (SwiftData models stay in app target).
@MainActor
public protocol CalendarPersistencePort: AnyObject {
    var calendarDidChangeToken: Int { get }
    var profileDisplayName: String? { get }

    func notifyCalendarDidChange()
    func calendarEventEntity(id: UUID) -> CalendarStoredEvent?
    func semester(id: UUID) -> CalendarSemesterRecord?
    func removeAutoLinkedCourse(code: String)

    @discardableResult
    func addCalendarEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        allDay: Bool,
        semesterID: UUID?,
        notes: String?,
        location: String?
    ) -> UUID

    func deleteCalendarEvent(id: UUID)
    func updateCalendarEvent(
        id: UUID,
        title: String,
        startDate: Date,
        endDate: Date,
        allDay: Bool,
        semesterID: UUID?,
        notes: String?,
        location: String?,
        recurrenceRule: String?
    )
    func updateCalendarEventTimes(id: UUID, startDate: Date, endDate: Date)
    func bulkDeleteCalendarEvents(withUUIDs uuids: [UUID])
    func fetchCalendarEvents(semesterID: UUID, start: Date, end: Date) -> [CalendarStoredEvent]
    func fetchOverlappingEvents(start: Date, end: Date, excludingEventID: UUID?) -> [CalendarStoredEvent]
    func fetchPlannerTask(id: UUID) -> CalendarPlannerTaskRecord?
    func setTaskCompleted(id: UUID, completed: Bool)
}

/// Repository-level writes used by `CalendarEventWritePipeline`.
@MainActor
public protocol CalendarWriteRepositoryPort: AnyObject {
    func resolvePlannerLinks(semesterID: UUID?, courseID: UUID?) -> (semesterID: UUID?, courseID: UUID?)
    func createCalendarEvent(input: CalendarEventWriteInput, semesterID: UUID?, courseID: UUID?) throws -> CalendarStoredEvent
    func updateCalendarEvent(id: UUID, input: CalendarEventWriteInput, semesterID: UUID?, courseID: UUID?) throws
    func deleteCalendarEvent(id: UUID) throws
    func patchCalendarEventColor(id: UUID, customColorHex: String) throws
    func patchCalendarEventRecurrence(id: UUID, recurrenceRule: String?) throws
    func fetchCalendarEvent(id: UUID) throws -> CalendarStoredEvent?
    func fetchTasks(dueFrom: Date, dueBefore: Date, limit: Int) throws -> [CalendarPlannerTaskRecord]
    func fetchPlannerTask(id: UUID) throws -> CalendarPlannerTaskRecord?
    func createPlannerTask(
        title: String,
        dueDate: Date?,
        semesterID: UUID?,
        courseID: UUID?,
        notes: String?
    ) throws -> UUID
    func updatePlannerTask(
        id: UUID,
        title: String,
        dueDate: Date?,
        semesterID: UUID?,
        courseID: UUID?,
        notes: String?,
        isCompleted: Bool
    ) throws
    func deletePlannerTask(id: UUID) throws
    func bumpProfileRevision()
    func flushPendingWrites()
}

@MainActor
public enum CalendarPersistenceAccess {
    public static weak var persistence: (any CalendarPersistencePort)?
    public static weak var writeRepository: (any CalendarWriteRepositoryPort)?
}
