// CalendarPersistencePort+App.swift
// Feature: Calendar
// Purpose: Wire local persistence into CollegeCalendar package ports (ADR 004).

import CollegeCalendar
import Foundation
import SwiftData

@MainActor
final class CalendarPersistencePortAdapter: CalendarPersistencePort {
    private let backend: CollegePersistence

    init(backend: CollegePersistence) {
        self.backend = backend
    }

    var calendarDidChangeToken: Int { backend.calendarDidChangeToken }
    var profileDisplayName: String? { backend.profile?.name }

    func notifyCalendarDidChange() {
        backend.notifyCalendarDidChange()
    }

    func calendarEventEntity(id: UUID) -> CalendarStoredEvent? {
        backend.calendarEventEntity(id: id).map(CalendarStoredEvent.init(event:))
    }

    func calendarEventEntities(ids: [UUID]) -> [CalendarStoredEvent] {
        backend.calendarEventEntities(ids: ids).map(CalendarStoredEvent.init(event:))
    }

    func semester(id: UUID) -> CalendarSemesterRecord? {
        backend.semester(with: id).map { CalendarSemesterRecord(id: $0.id, name: $0.name) }
    }

    @discardableResult
    func addCalendarEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        allDay: Bool,
        semesterID: UUID?,
        notes: String?,
        location: String?
    ) -> UUID {
        let semester = semesterID.flatMap { backend.semester(with: $0) }
        return backend.addCalendarEvent(
            title: title,
            startDate: startDate,
            endDate: endDate,
            allDay: allDay,
            semester: semester,
            notes: notes,
            location: location
        )
    }

    func deleteCalendarEvent(id: UUID) {
        backend.deleteCalendarEvent(id: id)
    }

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
    ) {
        let semester = semesterID.flatMap { backend.semester(with: $0) }
        backend.updateCalendarEvent(
            id: id,
            title: title,
            startDate: startDate,
            endDate: endDate,
            allDay: allDay,
            semester: semester,
            notes: notes,
            location: location,
            recurrenceRule: recurrenceRule
        )
    }

    func updateCalendarEventTimes(id: UUID, startDate: Date, endDate: Date) {
        backend.updateCalendarEventTimes(id: id, startDate: startDate, endDate: endDate)
    }

    func bulkDeleteCalendarEvents(withUUIDs uuids: [UUID]) {
        backend.bulkDeleteCalendarEvents(withUUIDs: uuids)
    }

    func fetchCalendarEvents(semesterID: UUID, start: Date, end: Date) -> [CalendarStoredEvent] {
        guard let semester = backend.semester(with: semesterID) else { return [] }
        return backend.fetchCalendarEvents(semester: semester, start: start, end: end)
            .map(CalendarStoredEvent.init(event:))
    }

    func fetchOverlappingEvents(start: Date, end: Date, excludingEventID: UUID?) -> [CalendarStoredEvent] {
        let repo = backend.calendarRepository
        guard let events = try? repo.fetchEventsOverlapping(start: start, end: end, limit: 200) else {
            return []
        }
        return events
            .filter { excludingEventID == nil || $0.id != excludingEventID }
            .map(CalendarStoredEvent.init(event:))
    }

    func fetchPlannerTask(id: UUID) -> CalendarPlannerTaskRecord? {
        try? backend.calendarRepository.fetchPlannerTask(id: id)
            .map { CalendarPlannerTaskRecord(id: $0.id, title: $0.title, dueDate: $0.dueDate) }
    }

    func setTaskCompleted(id: UUID, completed: Bool) {
        backend.setTaskCompleted(id: id, completed: completed)
    }

    func removeAutoLinkedCourse(code: String) {
        backend.removeAutoLinkedCourse(code: code)
    }
}

@MainActor
final class CalendarWriteRepositoryPortAdapter: CalendarWriteRepositoryPort {
    private let store: AppDataStore

    init(store: AppDataStore = .shared) {
        self.store = store
    }

    func resolvePlannerLinks(semesterID: UUID?, courseID: UUID?) -> (semesterID: UUID?, courseID: UUID?) {
        let (semester, course) = store.calendarRepository.resolvePlannerLinks(
            semesterID: semesterID,
            courseID: courseID,
            profileRepository: store.profileRepository
        )
        return (semester?.id, course?.id)
    }

    func createCalendarEvent(
        input: CalendarEventWriteInput,
        semesterID: UUID?,
        courseID: UUID?
    ) throws -> CalendarStoredEvent {
        let (semester, course) = store.calendarRepository.resolvePlannerLinks(
            semesterID: semesterID,
            courseID: courseID,
            profileRepository: store.profileRepository
        )
        let event = try store.calendarRepository.createCalendarEvent(
            input: input,
            semester: semester,
            course: course
        )
        return CalendarStoredEvent(event: event)
    }

    func updateCalendarEvent(
        id: UUID,
        input: CalendarEventWriteInput,
        semesterID: UUID?,
        courseID: UUID?
    ) throws {
        let (semester, course) = store.calendarRepository.resolvePlannerLinks(
            semesterID: semesterID,
            courseID: courseID,
            profileRepository: store.profileRepository
        )
        try store.calendarRepository.updateCalendarEvent(
            id: id,
            input: input,
            semester: semester,
            course: course
        )
    }

    func deleteCalendarEvent(id: UUID) throws {
        try store.calendarRepository.deleteCalendarEvent(id: id)
    }

    func patchCalendarEventColor(id: UUID, customColorHex: String) throws {
        try store.calendarRepository.patchCalendarEventColor(id: id, customColorHex: customColorHex)
    }

    func patchCalendarEventRecurrence(id: UUID, recurrenceRule: String?) throws {
        try store.calendarRepository.patchCalendarEventRecurrence(id: id, recurrenceRule: recurrenceRule)
    }

    func fetchCalendarEvent(id: UUID) throws -> CalendarStoredEvent? {
        try store.calendarRepository.fetchCalendarEvent(id: id).map(CalendarStoredEvent.init(event:))
    }

    func fetchTasks(dueFrom: Date, dueBefore: Date, limit: Int) throws -> [CalendarPlannerTaskRecord] {
        try store.calendarRepository.fetchTasks(dueFrom: dueFrom, dueBefore: dueBefore, limit: limit)
            .map { CalendarPlannerTaskRecord(id: $0.id, title: $0.title, dueDate: $0.dueDate) }
    }

    func fetchPlannerTask(id: UUID) throws -> CalendarPlannerTaskRecord? {
        try store.calendarRepository.fetchPlannerTask(id: id)
            .map { CalendarPlannerTaskRecord(id: $0.id, title: $0.title, dueDate: $0.dueDate) }
    }

    func createPlannerTask(
        title: String,
        dueDate: Date?,
        semesterID: UUID?,
        courseID: UUID?,
        notes: String?
    ) throws -> UUID {
        let (semester, course) = store.calendarRepository.resolvePlannerLinks(
            semesterID: semesterID,
            courseID: courseID,
            profileRepository: store.profileRepository
        )
        return try store.calendarRepository.createPlannerTask(
            title: title,
            dueDate: dueDate,
            semester: semester,
            course: course,
            notes: notes
        ).id
    }

    func updatePlannerTask(
        id: UUID,
        title: String,
        dueDate: Date?,
        semesterID: UUID?,
        courseID: UUID?,
        notes: String?,
        isCompleted: Bool
    ) throws {
        let (semester, course) = store.calendarRepository.resolvePlannerLinks(
            semesterID: semesterID,
            courseID: courseID,
            profileRepository: store.profileRepository
        )
        if let task = try store.calendarRepository.fetchPlannerTask(id: id) {
            task.isCompleted = isCompleted
        }
        try store.calendarRepository.updatePlannerTask(
            id: id,
            title: title,
            dueDate: dueDate,
            semester: semester,
            course: course,
            notes: notes
        )
    }

    func deletePlannerTask(id: UUID) throws {
        try store.calendarRepository.deletePlannerTask(id: id)
    }

    func bumpProfileRevision() {
        store.bumpProfileRevision()
    }

    func flushPendingWrites() {
        ModelMergeCoalescer.flushNow()
    }
}

extension CalendarStoredEvent {
    init(event: CalendarEvent) {
        let code = event.course?.code.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.init(
            id: event.id,
            title: event.title,
            notes: event.notes,
            location: event.location,
            startDate: event.startDate,
            endDate: event.endDate,
            allDay: event.allDay,
            providerSource: event.providerSource,
            customColorHex: event.customColorHex,
            recurrenceRule: event.recurrenceRule,
            providerEventId: event.providerEventId,
            attendeesJSON: event.attendeesJSON,
            courseID: event.course?.id,
            courseCode: code.isEmpty ? nil : code,
            semesterID: event.semester?.id
        )
    }
}

@MainActor
enum CalendarPersistencePortBootstrap {
    private static var retainedPersistence: CalendarPersistencePortAdapter?
    private static var retainedWriteRepository: CalendarWriteRepositoryPortAdapter?
    private static var retainedGoogleAuth: GoogleCalendarAuthPortAdapter?

    static func wire(persistence: CollegePersistence = .shared, store: AppDataStore = .shared) {
        let persistenceAdapter = CalendarPersistencePortAdapter(backend: persistence)
        let writeAdapter = CalendarWriteRepositoryPortAdapter(store: store)
        let authAdapter = GoogleCalendarAuthPortAdapter()
        retainedPersistence = persistenceAdapter
        retainedWriteRepository = writeAdapter
        retainedGoogleAuth = authAdapter
        CalendarPersistenceAccess.persistence = persistenceAdapter
        CalendarPersistenceAccess.writeRepository = writeAdapter
        GoogleCalendarAuthAccess.service = authAdapter
    }
}
