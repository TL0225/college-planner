// CollegePersistence+Calendar.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CollegePersistence+Calendar.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension CollegePersistence {
    func bulkDeleteCalendarEvents(withUUIDs uuids: [UUID]) {
        guard !uuids.isEmpty else { return }
        let repo = calendarRepository
        for id in uuids {
            try? repo.deleteCalendarEvent(id: id)
        }
        notifyCalendarDidChange()
    }

    func saveCalendarChanges() {
        _ = try? appDataStore.profileSave()
        notifyCalendarDidChange()
    }

    func deleteCalendarEvent(id: UUID) {
        try? calendarRepository.deleteCalendarEvent(id: id)
        saveCalendarChanges()
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
        recurrenceRule: String? = nil
    ) {
        try? calendarRepository.updateCalendarEvent(
            id: id,
            title: title,
            startDate: startDate,
            endDate: endDate,
            allDay: allDay,
            semester: semester,
            course: course,
            notes: notes,
            location: location,
            recurrenceRule: recurrenceRule
        )
        saveCalendarChanges()
    }

    func fetchCourse(id: UUID) -> PlannerCourse? {
        try? profileRepository.fetchCourse(id: id)
    }

    @discardableResult
    func addCalendarEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        allDay: Bool,
        semester: PlannerSemester? = nil,
        course: PlannerCourse? = nil,
        notes: String? = nil,
        location: String? = nil,
        brightspaceAnnouncementId: String? = nil
    ) -> UUID {
        do {
            let event = try calendarRepository.createCalendarEvent(
                title: title,
                startDate: startDate,
                endDate: endDate,
                allDay: allDay,
                semester: semester,
                course: course,
                notes: notes,
                location: location,
                brightspaceAnnouncementId: brightspaceAnnouncementId
            )
            _ = try? appDataStore.profileSave()
            notifyCalendarDidChange()
            return event.id
        } catch {
            AppLogger.shared.error("addCalendarEvent failed: \(error)")
            return UUID()
        }
    }

    func fetchUnlinkedCalendarEvents() -> [CalendarEvent] {
        let twoYearsAgo = Calendar.current.date(byAdding: .year, value: -2, to: Date()) ?? Date()
        let cutoff = twoYearsAgo
        var descriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { event in
                event.course == nil && event.startDate >= cutoff
            },
            sortBy: [SortDescriptor(\.startDate)]
        )
        descriptor.fetchLimit = 5000
        return (try? profileContext.fetch(descriptor)) ?? []
    }

    func mergeCourseDuplicates() {
        try? profileRepository.mergeCourseDuplicates()
        fetchSemesters()
        bumpProfileRevision()
    }

    func findOrCreateCourse(code: String, in semester: PlannerSemester) -> (PlannerCourse, Bool) {
        let upperCode = code.uppercased()
        if let existing = (semester.courses ?? []).first(where: { course in
            let stored = course.code.uppercased()
            return stored == upperCode || stored.hasPrefix(upperCode) || upperCode.hasPrefix(stored)
        }) {
            return (existing, false)
        }
        let catalog = getCatalogCourse(code: upperCode)
        let rawName = catalog?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let courseName = rawName.isEmpty ? upperCode : rawName
        let credits = catalog.map { Int($0.credits) } ?? 3
        let course = addCourse(
            to: semester,
            code: upperCode,
            name: courseName,
            credits: credits,
            status: "In Progress",
            gradingType: "Letter Grade",
            professor: nil
        )
        course.autoLinked = true
        course.catalogCourseID = catalog?.id
        return (course, true)
    }

    func bulkLinkCalendarEvents(
        _ events: [CalendarEvent],
        to course: PlannerCourse,
        semester: PlannerSemester
    ) {
        guard !events.isEmpty else { return }
        let now = Date()
        for event in events {
            event.course = course
            event.semester = semester
            event.lastUpdated = now
        }
        saveCalendarChanges()
    }

    func fetchCatalogCourseForCode(_ code: String) -> CourseCatalog? {
        getCatalogCourse(code: code) ?? getCatalogCourseMatching(code: code)
    }

    func setTaskCompleted(id: UUID, completed: Bool) {
        try? calendarRepository.setPlannerTaskCompleted(id: id, completed: completed)
        _ = try? appDataStore.profileSave()
        notifyCalendarDidChange()
    }

    func updateCalendarEventTimes(id: UUID, startDate: Date, endDate: Date) {
        try? calendarRepository.updateCalendarEventTimes(id: id, startDate: startDate, endDate: endDate)
        saveCalendarChanges()
    }

    func announcementExists(brightspaceAnnouncementId: String) -> Bool {
        let trimmed = brightspaceAnnouncementId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return calendarRepository.announcementExists(brightspaceAnnouncementId: trimmed)
    }

    func fetchCalendarEvents(
        semester: PlannerSemester,
        start: Date,
        end: Date
    ) -> [CalendarEvent] {
        let semesterID = semester.id
        var descriptor = FetchDescriptor<CalendarEvent>(
            predicate: #Predicate { event in
                event.semester?.id == semesterID
                    && event.endDate >= start
                    && event.startDate <= end
            },
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )
        descriptor.fetchLimit = 500
        return (try? profileContext.fetch(descriptor)) ?? []
    }

    func upsertGradingCategories(
        for course: PlannerCourse,
        items: [SyllabusGradingItem],
        source: String
    ) -> [CourseGradingCategory] {
        guard !items.isEmpty else { return [] }
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        var upserted: [CourseGradingCategory] = []
        var existing = course.gradingCategories ?? []

        for item in items {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let category: CourseGradingCategory
            if let match = existing.first(where: {
                $0.name.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(name) == .orderedSame
            }) {
                category = match
            } else {
                category = CourseGradingCategory(name: name)
                category.course = course
                profileContext.insert(category)
                existing.append(category)
            }
            category.weightPercent = item.weightPercent
            category.notes = item.notes
            category.source = trimmedSource.isEmpty ? nil : trimmedSource
            category.lastUpdated = .now
            upserted.append(category)
        }

        if !upserted.isEmpty {
            _ = try? appDataStore.profileSave()
            bumpProfileRevision()
        }
        return upserted
    }

    /// Removes academics sidebar auto-linked planner courses (and linked calendar rows via cascade).
    func removeAutoLinkedCourse(code: String) {
        let upper = code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !upper.isEmpty else { return }
        let matches = (try? profileRepository.fetchCourses(matchingCode: upper, limit: 50)) ?? []
        let targets = matches.filter(\.autoLinked)
        guard !targets.isEmpty else { return }
        for course in targets {
            deleteCourse(id: course.id)
        }
        notifyCalendarDidChange()
    }

}