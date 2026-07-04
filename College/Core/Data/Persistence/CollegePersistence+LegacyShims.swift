// CollegePersistence+LegacyShims.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CollegePersistence+LegacyShims.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// Legacy forwards and local store-native task/vault helpers (Phase 7f Batch E).
@MainActor
extension CollegePersistence {
    func archiveCourse(_ course: PlannerCourse) {
        course.isArchived = true
        course.status = "Archived"
        _ = try? appDataStore.profileSave()
        fetchSemesters()
        bumpProfileRevision()
    }

    /// Reverses `archiveCourse`, restoring planner visibility and the prior status.
    func unarchiveCourse(_ course: PlannerCourse, restoringStatus previousStatus: String) {
        course.isArchived = false
        course.status = previousStatus
        _ = try? appDataStore.profileSave()
        fetchSemesters()
        bumpProfileRevision()
    }

    func ensureCourseScheduledInPlanner(
        courseCode: String,
        courseName: String,
        creditsText: String,
        semesterText: String,
        status: String,
        gradingType: String,
        professor: String?
    ) {
        let normalizedCode = courseCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !normalizedCode.isEmpty,
              let parsed = Self.parseSemesterText(semesterText) else { return }

        let plan = getActivePlan() ?? addPlan(name: "Plan 1", type: "Primary", major: "", minor: "", concentration: "")
        let semester = semesters.first(where: {
            Int($0.year) == parsed.year && $0.season.caseInsensitiveCompare(parsed.season) == .orderedSame
        }) ?? addSemester(to: plan, name: "\(parsed.season) \(parsed.year)", year: parsed.year, season: parsed.season)

        let finalStatus: String = {
            let s = status.trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? "Not Planned" : s
        }()

        if let existing = semesters.flatMap({ $0.courses ?? [] }).first(where: {
            $0.code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == normalizedCode
        }) {
            existing.semester = semester
            existing.status = finalStatus
            existing.gradingType = gradingType
            existing.professor = professor
            if existing.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                existing.name = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if existing.credits <= 0 {
                let parsedCredits = Int((Double(creditsText) ?? 0).rounded())
                if parsedCredits > 0 {
                    existing.credits = Int16(parsedCredits)
                } else if let catalog = getCatalogCourse(code: normalizedCode), catalog.credits > 0 {
                    existing.credits = catalog.credits
                    existing.catalogCourseID = catalog.id
                }
            }
            _ = try? appDataStore.profileSave()
            fetchSemesters()
            bumpProfileRevision()
            return
        }

        let parsedCredits = Int((Double(creditsText) ?? 0).rounded())
        let catalog = getCatalogCourse(code: normalizedCode)
        let credits = parsedCredits > 0 ? parsedCredits : Int(catalog?.credits ?? 0)
        let name: String = {
            let trimmedName = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedName.isEmpty { return trimmedName }
            return (catalog?.title ?? normalizedCode).trimmingCharacters(in: .whitespacesAndNewlines)
        }()

        let newCourse = addCourse(
            to: semester,
            code: normalizedCode,
            name: name,
            credits: max(0, credits),
            status: finalStatus,
            gradingType: gradingType,
            professor: professor
        )
        newCourse.catalogCourseID = catalog?.id
        _ = try? appDataStore.profileSave()
        fetchSemesters()
        bumpProfileRevision()
    }

    @discardableResult
    func upsertCourseInstructorContact(
        courseCode: String,
        professorName: String?,
        email: String?,
        contactMethod: String?,
        officeHours: String?,
        overwriteExisting: Bool = false
    ) -> Bool {
        let normalizedCode = courseCode
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !normalizedCode.isEmpty else { return false }

        var didChange = false
        if let university = getActiveUniversity(),
           let repo = catalogRepository {
            didChange = (try? repo.upsertCourseInstructorContact(
                universityID: university.id,
                courseCode: normalizedCode,
                professorName: professorName,
                email: email,
                contactMethod: contactMethod,
                officeHours: officeHours,
                overwriteExisting: overwriteExisting
            )) ?? false
            if didChange {
                _ = try? appDataStore.catalogSave()
            }
        }

        if let planned = semesters.flatMap({ $0.courses ?? [] }).first(where: {
            $0.code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == normalizedCode
        }) {
            let trimmedName = professorName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmedName.isEmpty, overwriteExisting || (planned.professor ?? "").isEmpty {
                planned.professor = trimmedName
                didChange = true
            }
            if didChange {
                _ = try? appDataStore.profileSave()
                bumpProfileRevision()
            }
        }
        return didChange
    }

    @discardableResult
    func updateCourseOverrideSyllabus(
        courseCode: String,
        fileName: String?,
        bookmarkData: Data?,
        fileSizeBytes: Int64?,
        uploadedAt: Date?
    ) -> Bool {
        guard let university = getActiveUniversity(),
              let repo = catalogRepository else { return false }
        let changed = (try? repo.updateCourseOverrideSyllabus(
            universityID: university.id,
            courseCode: courseCode,
            fileName: fileName,
            bookmarkData: bookmarkData,
            fileSizeBytes: fileSizeBytes,
            uploadedAt: uploadedAt
        )) ?? false
        if changed {
            _ = try? appDataStore.catalogSave()
        }
        return changed
    }

    func deleteCourseOverride(courseCode: String) {
        guard let university = getActiveUniversity(),
              let repo = catalogRepository else { return }
        try? repo.deleteCourseOverride(universityID: university.id, courseCode: courseCode)
        _ = try? appDataStore.catalogSave()
    }

    private static func parseSemesterText(_ text: String) -> (season: String, year: Int)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        let seasons = ["fall", "spring", "summer", "winter"]
        guard let seasonToken = seasons.first(where: { lower.contains($0) }) else { return nil }
        let year: Int? = {
            if let re = try? NSRegularExpression(pattern: "\\b(\\d{4})\\b"),
               let m = re.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
               let r = Range(m.range(at: 1), in: lower) {
                return Int(lower[r])
            }
            if let re = try? NSRegularExpression(pattern: "\\b(\\d{2})\\b"),
               let m = re.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
               let r = Range(m.range(at: 1), in: lower),
               let yy = Int(lower[r]) {
                return 2000 + yy
            }
            return nil
        }()
        guard let year, year > 0 else { return nil }
        let season = seasonToken.prefix(1).uppercased() + seasonToken.dropFirst()
        return (season, year)
    }

    @discardableResult
    func addTask(
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
        lmsItemId: String? = nil
    ) -> UUID {
        do {
            let task = try calendarRepository.createPlannerTask(
                title: title,
                dueDate: dueDate,
                semester: semester,
                course: course,
                notes: notes,
                priority: priority,
                categoryName: categoryName,
                gradingCategory: gradingCategory,
                categoryWeightPercent: categoryWeightPercent,
                weightPercent: weightPercent,
                estimatedEffortMinutes: estimatedEffortMinutes,
                lmsItemId: lmsItemId
            )
            _ = try? appDataStore.profileSave()
            notifyCalendarDidChange()
            return task.id
        } catch {
            AppLogger.shared.error("addTask failed: \(error)")
            return UUID()
        }
    }

    func updateTask(
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
    ) {
        do {
            try calendarRepository.updatePlannerTask(
                id: id,
                title: title,
                dueDate: dueDate,
                semester: semester,
                course: course,
                notes: notes,
                priority: priority,
                categoryName: categoryName,
                gradingCategory: gradingCategory,
                categoryWeightPercent: categoryWeightPercent,
                weightPercent: weightPercent,
                estimatedEffortMinutes: estimatedEffortMinutes
            )
            _ = try? appDataStore.profileSave()
            notifyCalendarDidChange()
        } catch {
            AppLogger.shared.error("updateTask failed: \(error)")
        }
    }

    func deleteTask(id: UUID) {
        try? calendarRepository.deletePlannerTask(id: id)
        _ = try? appDataStore.profileSave()
        notifyCalendarDidChange()
    }

    func cleanupJobBoardRelationshipOrphans() {
        try? careerRepository.cleanupJobBoardRelationshipOrphans()
    }
}