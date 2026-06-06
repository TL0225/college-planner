// CalendarEventWritePipeline.swift
// Feature: Calendar
// Purpose: Single chokepoint for calendar event creates/updates/deletes from any feature surface.

import CollegePlatform
import Foundation

public struct CalendarEventWriteInput: Sendable {
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var allDay: Bool
    public var semesterID: UUID?
    public var courseID: UUID?
    public var notes: String?
    public var location: String?
    public var customColorHex: String?
    public var recurrenceRule: String?
    public var guestsJSON: String?
    public var brightspaceAnnouncementId: String?

    public init(
        title: String,
        startDate: Date,
        endDate: Date,
        allDay: Bool,
        semesterID: UUID? = nil,
        courseID: UUID? = nil,
        notes: String? = nil,
        location: String? = nil,
        customColorHex: String? = nil,
        recurrenceRule: String? = nil,
        guestsJSON: String? = nil,
        brightspaceAnnouncementId: String? = nil
    ) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.allDay = allDay
        self.semesterID = semesterID
        self.courseID = courseID
        self.notes = notes
        self.location = location
        self.customColorHex = customColorHex
        self.recurrenceRule = recurrenceRule
        self.guestsJSON = guestsJSON
        self.brightspaceAnnouncementId = brightspaceAnnouncementId
    }
}

public struct CalendarEventWriteOptions: Sendable {
    public var skipExport: Bool = false
    public var skipReminders: Bool = false
    public var exportGoogleCalendarID: String?
    public var exportAppleCalendarName: String?
    public var reminderLeadMinutes: [Int]?

    public init(
        skipExport: Bool = false,
        skipReminders: Bool = false,
        exportGoogleCalendarID: String? = nil,
        exportAppleCalendarName: String? = nil,
        reminderLeadMinutes: [Int]? = nil
    ) {
        self.skipExport = skipExport
        self.skipReminders = skipReminders
        self.exportGoogleCalendarID = exportGoogleCalendarID
        self.exportAppleCalendarName = exportAppleCalendarName
        self.reminderLeadMinutes = reminderLeadMinutes
    }
}

/// Single chokepoint for calendar event creates/updates/deletes from any feature surface.
@MainActor
public final class CalendarEventWritePipeline {
    public static let shared = CalendarEventWritePipeline()

    private let changePublisher: CalendarChangePublisher
    private let healthStore: IntegrationHealthStore

    public init(
        changePublisher: CalendarChangePublisher = CalendarChangePublisher.shared,
        healthStore: IntegrationHealthStore = IntegrationHealthStore.shared
    ) {
        self.changePublisher = changePublisher
        self.healthStore = healthStore
    }

    public func create(
        input: CalendarEventWriteInput,
        options: CalendarEventWriteOptions = .init()
    ) async throws -> UUID {
        let event = try createStoreCalendarEvent(input: input)

        if !options.skipExport {
            exportAfterWrite(eventID: event.id, options: options)
        }

        if !options.skipReminders {
            scheduleReminder(
                eventID: event.id,
                title: input.title,
                start: input.startDate,
                leadMinutes: options.reminderLeadMinutes
            )
        }

        notifyChange(reason: .userEdit, eventIDs: [event.id])
        return event.id
    }

    public func update(
        eventID: UUID,
        input: CalendarEventWriteInput,
        options: CalendarEventWriteOptions = .init()
    ) async throws {
        try updateStoreCalendarEvent(id: eventID, input: input)

        if !options.skipExport {
            exportAfterWrite(eventID: eventID, options: options)
        }

        if !options.skipReminders {
            scheduleReminder(
                eventID: eventID,
                title: input.title,
                start: input.startDate,
                leadMinutes: options.reminderLeadMinutes
            )
        }

        notifyChange(reason: .userEdit, eventIDs: [eventID])
    }

    public func delete(eventID: UUID) async throws {
        await deleteRemoteCopies(for: eventID)

        guard let repo = CalendarPersistenceAccess.writeRepository else {
            throw CalendarEventWritePipelineError.persistenceUnavailable
        }
        try repo.deleteCalendarEvent(id: eventID)
        repo.flushPendingWrites()
        repo.bumpProfileRevision()
        CalendarPersistenceAccess.persistence?.notifyCalendarDidChange()

        CalendarReminderScheduler.shared.cancelReminders(eventID: eventID)
        notifyChange(reason: .delete, eventIDs: [eventID])
    }

    public func migrateColorOverridesFromUserDefaults() async {
        let pairs = EventColorOverrides.allStoredOverrides()
        guard !pairs.isEmpty, let repo = CalendarPersistenceAccess.writeRepository else { return }

        for (eventID, hex) in pairs {
            do {
                try repo.patchCalendarEventColor(id: eventID, customColorHex: hex)
                EventColorOverrides.clearColor(for: eventID)
            } catch {
                continue
            }
        }
        repo.flushPendingWrites()
        notifyChange(reason: .migration, eventIDs: [])
    }

    private func createStoreCalendarEvent(input: CalendarEventWriteInput) throws -> CalendarStoredEvent {
        guard let repo = CalendarPersistenceAccess.writeRepository else {
            throw CalendarEventWritePipelineError.persistenceUnavailable
        }
        let links = repo.resolvePlannerLinks(semesterID: input.semesterID, courseID: input.courseID)
        let event = try repo.createCalendarEvent(
            input: input,
            semesterID: links.semesterID,
            courseID: links.courseID
        )
        repo.flushPendingWrites()
        repo.bumpProfileRevision()
        CalendarPersistenceAccess.persistence?.notifyCalendarDidChange()
        return event
    }

    private func updateStoreCalendarEvent(id: UUID, input: CalendarEventWriteInput) throws {
        guard let repo = CalendarPersistenceAccess.writeRepository else {
            throw CalendarEventWritePipelineError.persistenceUnavailable
        }
        let links = repo.resolvePlannerLinks(semesterID: input.semesterID, courseID: input.courseID)
        try repo.updateCalendarEvent(
            id: id,
            input: input,
            semesterID: links.semesterID,
            courseID: links.courseID
        )
        repo.flushPendingWrites()
        repo.bumpProfileRevision()
        CalendarPersistenceAccess.persistence?.notifyCalendarDidChange()
    }

    private func deleteRemoteCopies(for eventUUID: UUID) async {
        guard let manager = CalendarIntegrationBridge.manager else { return }
        if manager.googleStatus == .connected {
            try? await CalendarSyncCoordinator.google.deleteRemoteEvent(localEventID: eventUUID)
        }
        if manager.appleStatus == .connected {
            try? await CalendarSyncCoordinator.apple.deleteRemoteEvent(localEventID: eventUUID)
        }
        if manager.outlookStatus == .connected {
            try? await CalendarSyncCoordinator.outlook.deleteRemoteEvent(localEventID: eventUUID)
        }
    }

    private func exportAfterWrite(
        eventID: UUID,
        options: CalendarEventWriteOptions
    ) {
        Task {
            guard let manager = CalendarIntegrationBridge.manager else {
                healthStore.report(.google, .exportFailure("Calendar integration unavailable"))
                healthStore.report(.apple, .exportFailure("Calendar integration unavailable"))
                return
            }
            await CalendarSyncCoordinator.exportAfterWrite(
                eventID: eventID,
                options: options,
                manager: manager
            )
            if manager.googleStatus == .connected {
                healthStore.report(.google, .success)
            }
            if manager.appleStatus == .connected {
                healthStore.report(.apple, .success)
            }
        }
    }

    private func scheduleReminder(
        eventID: UUID,
        title: String,
        start: Date,
        leadMinutes: [Int]?
    ) {
        let leads: [Int]
        if let leadMinutes, !leadMinutes.isEmpty {
            leads = leadMinutes
        } else {
            let minutes = UserDefaults.standard.integer(forKey: "calendar.defaultReminderMinutes")
            leads = [minutes > 0 ? minutes : 15]
        }
        CalendarReminderScheduler.shared.reschedule(
            eventID: eventID,
            title: title,
            startDate: start,
            leadMinutes: leads
        )
    }

    private func notifyChange(reason: CalendarChangeReason, eventIDs: [UUID]) {
        let message = CalendarDidChangeMessage(reason: reason, eventIDs: eventIDs)
        NotificationCenter.default.post(
            name: .calendarDidChange,
            object: nil,
            userInfo: ["message": message]
        )
        changePublisher.bump()
        CalendarPersistenceAccess.persistence?.notifyCalendarDidChange()
    }
}

public extension CalendarChangePublisher {
    @MainActor static let shared = CalendarChangePublisher()
}

public extension IntegrationHealthStore {
    @MainActor static let shared = IntegrationHealthStore()
}
