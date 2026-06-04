// CalendarRepository+TaskWrites.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CalendarRepository+TaskWrites.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension CalendarRepository {
    @discardableResult
    func createPlannerTask(
        title: String,
        dueDate: Date?,
        semester: PlannerSemester? = nil,
        course: PlannerCourse? = nil,
        notes: String? = nil,
        priority: Int16 = 0,
        categoryName: String? = nil,
        gradingCategory: CourseGradingCategory? = nil,
        categoryWeightPercent: Double? = nil,
        weightPercent: Double? = nil,
        estimatedEffortMinutes: Int32? = nil,
        brightspaceItemId: String? = nil,
        id: UUID = UUID()
    ) throws -> PlannerTask {
        let now = Date()
        let task = PlannerTask(
            id: id,
            title: title.isEmpty ? "Task" : title,
            dueDate: dueDate,
            isCompleted: false,
            priority: priority,
            createdAt: now,
            lastUpdated: now
        )
        task.notes = notes
        task.categoryName = categoryName
        task.gradingCategory = gradingCategory
        task.categoryWeightPercent = categoryWeightPercent
        task.weightPercent = weightPercent
        task.estimatedEffortMinutes = estimatedEffortMinutes
        task.brightspaceItemId = brightspaceItemId
        task.semester = semester
        task.course = course
        context.insert(task)
        ModelMergeCoalescer.scheduleSave(context)
        return task
    }

    func updatePlannerTask(
        id: UUID,
        title: String,
        dueDate: Date?,
        semester: PlannerSemester? = nil,
        course: PlannerCourse? = nil,
        notes: String? = nil,
        priority: Int16 = 0,
        categoryName: String? = nil,
        gradingCategory: CourseGradingCategory? = nil,
        categoryWeightPercent: Double? = nil,
        weightPercent: Double? = nil,
        estimatedEffortMinutes: Int32? = nil
    ) throws {
        guard let task = try fetchPlannerTask(id: id) else { return }
        task.title = title.isEmpty ? task.title : title
        task.dueDate = dueDate
        task.semester = semester
        task.course = course
        task.notes = notes
        task.priority = priority
        task.categoryName = categoryName
        task.gradingCategory = gradingCategory
        task.categoryWeightPercent = categoryWeightPercent
        task.weightPercent = weightPercent
        task.estimatedEffortMinutes = estimatedEffortMinutes
        task.lastUpdated = Date()
        ModelMergeCoalescer.scheduleSave(context)
    }

    func setPlannerTaskCompleted(id: UUID, completed: Bool) throws {
        guard let task = try fetchPlannerTask(id: id) else { return }
        task.isCompleted = completed
        task.completedAt = completed ? Date() : nil
        task.lastUpdated = Date()
        ModelMergeCoalescer.scheduleSave(context)
    }

    func taskExists(brightspaceItemId: String) throws -> Bool {
        let trimmed = brightspaceItemId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        var descriptor = FetchDescriptor<PlannerTask>(
            predicate: #Predicate { $0.brightspaceItemId == trimmed }
        )
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
    }

    func resolvePlannerLinksForTask(
        semesterID: UUID?,
        courseID: UUID?,
        profileRepository: ProfileRepository
    ) -> (PlannerSemester?, PlannerCourse?) {
        let semester = semesterID.flatMap { try? profileRepository.fetchSemester(id: $0) }
        let course = courseID.flatMap { try? profileRepository.fetchCourse(id: $0) }
        return (semester, course)
    }
}