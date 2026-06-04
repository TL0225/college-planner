// CalendarEventWritePipeline+Overlay.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarEventWritePipelineError.
// Data: CollegePersistence / repositories when applicable.

import Foundation

extension CalendarEventWritePipeline {
    func writeFromOverlay(
        title: String,
        start: Date,
        end: Date,
        allDay: Bool,
        semester: PlannerSemester?,
        course: PlannerCourse?,
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
            semesterID: semester?.id,
            courseID: course?.id,
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

enum CalendarEventWritePipelineError: Error {
    case missingEventID
}
