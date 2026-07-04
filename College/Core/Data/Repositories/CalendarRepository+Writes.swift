// CalendarRepository+Writes.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CalendarRepository+Writes.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

// MARK: - Phase 7c calendar/task writes

extension CalendarRepository {
    func fetchCalendarEvent(id: UUID) throws -> CalendarEvent? {
        var descriptor = FetchDescriptor<CalendarEvent>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchCalendarEvents(ids: [UUID]) throws -> [CalendarEvent] {
        let targetIDs = ids
        guard !targetIDs.isEmpty else { return [] }
        let descriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate<CalendarEvent> { event in
                targetIDs.contains(event.id)
            }
        )
        return try context.fetch(descriptor)
    }

    func fetchPlannerTask(id: UUID) throws -> PlannerTask? {
        var descriptor = FetchDescriptor<PlannerTask>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @discardableResult
    func upsertCalendarEvent(
        id: UUID,
        title: String,
        startDate: Date,
        endDate: Date,
        allDay: Bool = false,
        notes: String? = nil,
        location: String? = nil,
        providerSource: String? = nil,
        providerEventId: String? = nil,
        customColorHex: String? = nil,
        recurrenceRule: String? = nil,
        attendeesJSON: String? = nil,
        lmsAnnouncementId: String? = nil,
        semester: PlannerSemester? = nil,
        course: PlannerCourse? = nil,
        createdAt: Date = .now,
        lastUpdated: Date = .now
    ) throws -> CalendarEvent {
        let event: CalendarEvent
        if let existing = try fetchCalendarEvent(id: id) {
            event = existing
        } else {
            event = CalendarEvent(
                id: id,
                title: title,
                startDate: startDate,
                endDate: endDate,
                allDay: allDay,
                createdAt: createdAt,
                lastUpdated: lastUpdated
            )
            context.insert(event)
        }
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.allDay = allDay
        event.notes = notes
        event.location = location
        event.createdAt = createdAt
        event.lastUpdated = lastUpdated
        event.providerSource = providerSource
        event.providerEventId = providerEventId
        event.customColorHex = customColorHex
        event.recurrenceRule = recurrenceRule
        event.attendeesJSON = attendeesJSON
        event.lmsAnnouncementId = lmsAnnouncementId
        event.semester = semester
        event.course = course
        ModelMergeCoalescer.scheduleSave(context)
        return event
    }

    func deleteCalendarEvent(id: UUID) throws {
        guard let event = try fetchCalendarEvent(id: id) else { return }
        context.delete(event)
        ModelMergeCoalescer.scheduleSave(context)
    }

    @discardableResult
    func upsertPlannerTask(
        id: UUID,
        title: String,
        dueDate: Date?,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        notes: String? = nil,
        priority: Int16 = 0,
        categoryName: String? = nil,
        categoryWeightPercent: Double? = nil,
        weightPercent: Double? = nil,
        estimatedEffortMinutes: Int32? = nil,
        lmsItemId: String? = nil,
        semester: PlannerSemester? = nil,
        course: PlannerCourse? = nil,
        gradingCategory: CourseGradingCategory? = nil,
        createdAt: Date = .now,
        lastUpdated: Date = .now
    ) throws -> PlannerTask {
        let task: PlannerTask
        if let existing = try fetchPlannerTask(id: id) {
            task = existing
        } else {
            task = PlannerTask(
                id: id,
                title: title,
                dueDate: dueDate,
                isCompleted: isCompleted,
                priority: priority,
                createdAt: createdAt,
                lastUpdated: lastUpdated
            )
            context.insert(task)
        }
        task.title = title
        task.dueDate = dueDate
        task.isCompleted = isCompleted
        task.completedAt = completedAt
        task.notes = notes
        task.priority = priority
        task.createdAt = createdAt
        task.lastUpdated = lastUpdated
        task.semester = semester
        task.course = course
        task.categoryName = categoryName
        task.categoryWeightPercent = categoryWeightPercent
        task.weightPercent = weightPercent
        task.estimatedEffortMinutes = estimatedEffortMinutes
        task.lmsItemId = lmsItemId
        task.gradingCategory = gradingCategory
        ModelMergeCoalescer.scheduleSave(context)
        return task
    }

    func deletePlannerTask(id: UUID) throws {
        guard let task = try fetchPlannerTask(id: id) else { return }
        context.delete(task)
        ModelMergeCoalescer.scheduleSave(context)
    }
}