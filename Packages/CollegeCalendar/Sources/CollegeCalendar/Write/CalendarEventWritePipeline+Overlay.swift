// CalendarEventWritePipeline+Overlay.swift
// Feature: Calendar
// Purpose: Overlay write helpers for calendar event editor surfaces.

import Foundation

public extension CalendarEventWritePipeline {
    func writeFromOverlay(
        title: String,
        start: Date,
        end: Date,
        allDay: Bool,
        semesterID: UUID?,
        courseID: UUID?,
        notes: String?,
        location: String?,
        customColorHex: String?,
        recurrenceRule: String?,
        guestsJSON: String?,
        existingEventID: UUID?,
        options: CalendarEventWriteOptions
    ) async throws -> UUID {
        let input = CalendarEventWriteInput(
            title: title,
            startDate: start,
            endDate: end,
            allDay: allDay,
            semesterID: semesterID,
            courseID: courseID,
            notes: notes,
            location: location,
            customColorHex: customColorHex,
            recurrenceRule: recurrenceRule,
            guestsJSON: guestsJSON
        )

        if let existingEventID {
            try await update(eventID: existingEventID, input: input, options: options)
            return existingEventID
        }

        return try await create(input: input, options: options)
    }
}

public enum CalendarEventWritePipelineError: Error {
    case missingEventID
    case persistenceUnavailable
}
