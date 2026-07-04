// CalendarRepository+EventWrites.swift
import CollegeCalendar
// Feature: Core/Data
// Purpose: Core/Data persistence — — CalendarRepository+EventWrites.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension CalendarRepository {
    func createCalendarEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        allDay: Bool,
        semester: PlannerSemester? = nil,
        course: PlannerCourse? = nil,
        notes: String? = nil,
        location: String? = nil,
        customColorHex: String? = nil,
        recurrenceRule: String? = nil,
        attendeesJSON: String? = nil,
        lmsAnnouncementId: String? = nil,
        providerSource: String? = "CollegeApp",
        id: UUID = UUID()
    ) throws -> CalendarEvent {
        let now = Date()
        let event = CalendarEvent(
            id: id,
            title: title.isEmpty ? "Untitled" : title,
            startDate: startDate,
            endDate: endDate,
            allDay: allDay,
            createdAt: now,
            lastUpdated: now
        )
        event.notes = notes
        event.location = location
        event.customColorHex = customColorHex?.isEmpty == true ? nil : customColorHex
        event.recurrenceRule = recurrenceRule
        event.attendeesJSON = attendeesJSON
        event.lmsAnnouncementId = lmsAnnouncementId
        event.providerSource = providerSource
        event.semester = semester
        event.course = course
        context.insert(event)
        ModelMergeCoalescer.scheduleSave(context)
        return event
    }

    func createCalendarEvent(
        input: CalendarEventWriteInput,
        semester: PlannerSemester? = nil,
        course: PlannerCourse? = nil
    ) throws -> CalendarEvent {
        try createCalendarEvent(
            title: input.title,
            startDate: input.startDate,
            endDate: input.endDate,
            allDay: input.allDay,
            semester: semester,
            course: course,
            notes: input.notes,
            location: input.location,
            customColorHex: input.customColorHex,
            recurrenceRule: input.recurrenceRule,
            attendeesJSON: input.guestsJSON,
            lmsAnnouncementId: input.lmsAnnouncementId
        )
    }

    func updateCalendarEvent(
        id: UUID,
        title: String,
        startDate: Date,
        endDate: Date,
        allDay: Bool,
        semester: PlannerSemester? = nil,
        course: PlannerCourse? = nil,
        notes: String? = nil,
        location: String? = nil,
        customColorHex: String? = nil,
        recurrenceRule: String? = nil,
        attendeesJSON: String? = nil,
        lmsAnnouncementId: String? = nil
    ) throws {
        guard let event = try fetchCalendarEvent(id: id) else { return }
        if !title.isEmpty { event.title = title }
        if startDate != .distantPast { event.startDate = startDate }
        if endDate != .distantPast { event.endDate = endDate }
        event.allDay = allDay
        event.notes = notes
        event.location = location
        event.semester = semester
        event.course = course
        if let customColorHex {
            event.customColorHex = customColorHex.isEmpty ? nil : customColorHex
        }
        if let recurrenceRule {
            event.recurrenceRule = recurrenceRule
        }
        if let attendeesJSON {
            event.attendeesJSON = attendeesJSON
        }
        if let lmsAnnouncementId {
            event.lmsAnnouncementId = lmsAnnouncementId
        }
        if event.providerSource == nil || event.providerSource?.isEmpty == true {
            event.providerSource = "CollegeApp"
        }
        event.lastUpdated = Date()
        ModelMergeCoalescer.scheduleSave(context)
    }

    func updateCalendarEvent(
        id: UUID,
        input: CalendarEventWriteInput,
        semester: PlannerSemester? = nil,
        course: PlannerCourse? = nil
    ) throws {
        try updateCalendarEvent(
            id: id,
            title: input.title,
            startDate: input.startDate,
            endDate: input.endDate,
            allDay: input.allDay,
            semester: semester,
            course: course,
            notes: input.notes,
            location: input.location,
            customColorHex: input.customColorHex,
            recurrenceRule: input.recurrenceRule,
            attendeesJSON: input.guestsJSON,
            lmsAnnouncementId: input.lmsAnnouncementId
        )
    }

    func updateCalendarEventTimes(id: UUID, startDate: Date, endDate: Date) throws {
        guard let event = try fetchCalendarEvent(id: id) else { return }
        event.startDate = startDate
        event.endDate = endDate
        event.lastUpdated = Date()
        ModelMergeCoalescer.scheduleSave(context)
    }

    func patchCalendarEventColor(id: UUID, customColorHex: String?) throws {
        guard let event = try fetchCalendarEvent(id: id) else { return }
        event.customColorHex = customColorHex?.isEmpty == true ? nil : customColorHex
        event.lastUpdated = Date()
        ModelMergeCoalescer.scheduleSave(context)
    }

    func patchCalendarEventRecurrence(id: UUID, recurrenceRule: String?) throws {
        guard let event = try fetchCalendarEvent(id: id) else { return }
        event.recurrenceRule = recurrenceRule
        event.lastUpdated = Date()
        ModelMergeCoalescer.scheduleSave(context)
    }

    func resolvePlannerLinks(
        semesterID: UUID?,
        courseID: UUID?,
        profileRepository: ProfileRepository
    ) -> (PlannerSemester?, PlannerCourse?) {
        let semester = semesterID.flatMap { try? profileRepository.fetchSemester(id: $0) }
        let course = courseID.flatMap { try? profileRepository.fetchCourse(id: $0) }
        return (semester, course)
    }
}