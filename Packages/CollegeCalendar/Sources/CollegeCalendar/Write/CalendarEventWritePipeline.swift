// CalendarEventWritePipeline.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarEventWriteInput.
// Data: CollegePersistence / repositories when applicable.

import CollegePlatform
import Foundation
import SwiftData

struct CalendarEventWriteInput: Sendable {
    var title: String
    var startDate: Date
    var endDate: Date
    var allDay: Bool
    var semesterID: UUID?
    var courseID: UUID?
    var notes: String?
    var location: String?
    var customColorHex: String?
    var recurrenceRule: String?
    var guestsJSON: String?
    var brightspaceAnnouncementId: String?
}

struct CalendarEventWriteOptions: Sendable {
    var skipExport: Bool = false
    var skipReminders: Bool = false
    var exportGoogleCalendarID: String?
    var exportAppleCalendarName: String?
    var reminderLeadMinutes: [Int]?
}

/// Single chokepoint for calendar event creates/updates/deletes from any feature surface.
@MainActor
final class CalendarEventWritePipeline {
    static let shared = CalendarEventWritePipeline()

    private let changePublisher: CalendarChangePublisher
    private let healthStore: IntegrationHealthStore

    init(
        changePublisher: CalendarChangePublisher = CalendarChangePublisher.shared,
        healthStore: IntegrationHealthStore = IntegrationHealthStore.shared
    ) {
        self.changePublisher = changePublisher
        self.healthStore = healthStore
    }

    func create(
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

    func update(
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

    func delete(eventID: UUID) async throws {
        await deleteRemoteCopies(for: eventID)

        try AppDataStore.shared.calendarRepository.deleteCalendarEvent(id: eventID)
        ModelMergeCoalescer.flushNow()
        AppDataStore.shared.bumpProfileRevision()
        CollegePersistence.shared.notifyCalendarDidChange()

        CalendarReminderScheduler.shared.cancelReminders(eventID: eventID)
        notifyChange(reason: .delete, eventIDs: [eventID])
    }

    func migrateColorOverridesFromUserDefaults() async {
        let pairs = EventColorOverrides.allStoredOverrides()
        guard !pairs.isEmpty else { return }

        for (eventID, hex) in pairs {
            do {
                try AppDataStore.shared.calendarRepository.patchCalendarEventColor(
                    id: eventID,
                    customColorHex: hex
                )
                EventColorOverrides.clearColor(for: eventID)
            } catch {
                continue
            }
        }
        ModelMergeCoalescer.flushNow()
        notifyChange(reason: .migration, eventIDs: [])
    }

    // MARK: - Private

    private enum PipelineError: Error {
        case missingEvent
    }

    private func createStoreCalendarEvent(input: CalendarEventWriteInput) throws -> CalendarEvent {
        let store = AppDataStore.shared
        let (semester, course) = store.calendarRepository.resolvePlannerLinks(
            semesterID: input.semesterID,
            courseID: input.courseID,
            profileRepository: store.profileRepository
        )
        let event = try store.calendarRepository.createCalendarEvent(
            input: input,
            semester: semester,
            course: course
        )
        ModelMergeCoalescer.flushNow()
        store.bumpProfileRevision()
        CollegePersistence.shared.notifyCalendarDidChange()
        return event
    }

    private func updateStoreCalendarEvent(id: UUID, input: CalendarEventWriteInput) throws {
        let store = AppDataStore.shared
        let (semester, course) = store.calendarRepository.resolvePlannerLinks(
            semesterID: input.semesterID,
            courseID: input.courseID,
            profileRepository: store.profileRepository
        )
        try store.calendarRepository.updateCalendarEvent(
            id: id,
            input: input,
            semester: semester,
            course: course
        )
        ModelMergeCoalescer.flushNow()
        store.bumpProfileRevision()
        CollegePersistence.shared.notifyCalendarDidChange()
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

    @MainActor
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
        CollegePersistence.shared.notifyCalendarDidChange()
    }
}

extension CalendarChangePublisher {
    @MainActor static let shared = CalendarChangePublisher()
}

extension IntegrationHealthStore {
    @MainActor static let shared = IntegrationHealthStore()
}
