// CollegePersistence+PlannerWrites.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CollegePersistence+PlannerWrites.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension CollegePersistence {
    func updateSemesterDetails(id: UUID, season: String, year: Int) {
        try? profileRepository.updateSemesterDetails(id: id, season: season, year: year)
        fetchSemesters()
        bumpProfileRevision()
    }

    func deleteSemester(id: UUID) {
        try? profileRepository.deleteSemester(id: id)
        fetchSemesters()
        bumpProfileRevision()
    }

    func deleteCourse(id: UUID) {
        try? profileRepository.deleteCourse(id: id)
        fetchSemesters()
        bumpProfileRevision()
    }

    func commitPlanEdits(_ plan: PlannerPlan) {
        _ = plan
        _ = try? appDataStore.profileSave()
        bumpProfileRevision()
    }

    func addOrTagGenEdCourse(from catalogCourse: CourseCatalog) {
        addCatalogCourse(from: catalogCourse, targetSemesterID: nil, tagAsGenEd: true)
    }

    func findOrCreateSemester(season: String, year: Int) -> PlannerSemester {
        if let existing = semesters.first(where: {
            $0.season.caseInsensitiveCompare(season) == .orderedSame && Int($0.year) == year
        }) {
            return existing
        }
        let plan = getActivePlan() ?? addPlan(name: "Plan 1", type: "Primary", major: "", minor: "", concentration: "")
        return addSemester(to: plan, name: "\(season) \(year)", year: year, season: season)
    }

    func seasonOrder(for season: String) -> Int {
        Int(profileRepository.seasonOrder(for: season))
    }

    @discardableResult
    func addCourse(
        to semester: PlannerSemester,
        code: String,
        name: String,
        credits: Int,
        status: String,
        gradingType: String,
        professor: String?
    ) -> PlannerCourse {
        let order = Int32((semester.courses ?? []).count)
        let course = PlannerCourse(
            code: code,
            name: name,
            credits: Int16(credits),
            status: status,
            gradingType: gradingType,
            isCompleted: status == "Completed",
            sortOrder: order
        )
        course.professor = professor
        course.semester = semester
        profileContext.insert(course)
        _ = try? appDataStore.profileSave()
        fetchSemesters()
        bumpProfileRevision()
        return course
    }

    func activeUniversityHasCatalogCourses() -> Bool {
        guard let university = getActiveUniversity(),
              let repo = catalogRepository else { return false }
        return ((try? repo.fetchCatalogCoursesPage(universityID: university.id, offset: 0, limit: 1)) ?? []).isEmpty == false
    }

    /// Adds a catalog course to the plan (if missing), optionally tagging it for GenEd.
    func addCatalogCourse(from catalogCourse: CourseCatalog, targetSemesterID: UUID?, tagAsGenEd: Bool) {
        let code = catalogCourse.courseCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !code.isEmpty else { return }

        if let existing = plannedCourse(matchingCode: code) {
            if tagAsGenEd { existing.countsTowardGenEd = true }
            if existing.catalogCourseID == nil { existing.catalogCourseID = catalogCourse.id }
            if existing.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                existing.name = catalogCourse.title.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if existing.credits == 0 {
                let resolved = resolvedCatalogCredits(for: catalogCourse)
                if resolved > 0 { existing.credits = Int16(resolved) }
            }
            save()
            return
        }

        let targetSemester: PlannerSemester? = {
            if let targetSemesterID {
                return try? profileRepository.fetchSemester(id: targetSemesterID)
            }
            return nil
        }()

        guard let semester = targetSemester ?? defaultSemesterForNewCourses() else {
            AppNotificationCenter.shared.post(
                kind: .warning,
                title: "Add a Semester First",
                message: "Create a planned semester before adding courses from the catalog.",
                isDismissible: true,
                autoDismissAfter: 6
            )
            return
        }

        let resolvedCredits = resolvedCatalogCredits(for: catalogCourse)
        let newCourse = addCourse(
            to: semester,
            code: code,
            name: catalogCourse.title.trimmingCharacters(in: .whitespacesAndNewlines),
            credits: resolvedCredits,
            status: "Planned",
            gradingType: "Letter Grade",
            professor: nil
        )

        if tagAsGenEd { newCourse.countsTowardGenEd = true }
        newCourse.catalogCourseID = catalogCourse.id
        save()

        let capturedCode = newCourse.code
        let semesterID = semester.id
        Task { @MainActor in
            guard let sem = try? profileRepository.fetchSemester(id: semesterID) else { return }
            await CalendarCourseLinker.shared.scanAndLink(forCode: capturedCode, in: sem)
        }
    }

    private func plannedCourse(matchingCode code: String) -> PlannerCourse? {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { return nil }
        for semester in semesters {
            if let match = (semester.courses ?? []).first(where: {
                $0.code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == normalized
            }) {
                return match
            }
        }
        return nil
    }

    private func defaultSemesterForNewCourses() -> PlannerSemester? {
        semesters
            .filter(\.isPlanned)
            .sorted { lhs, rhs in
                if lhs.year != rhs.year { return lhs.year < rhs.year }
                return lhs.seasonOrder < rhs.seasonOrder
            }
            .first
    }

    private func resolvedCatalogCredits(for course: CourseCatalog) -> Int {
        let base = Int(course.credits)
        if base > 0 { return base }

        guard let desc = course.descriptionText?.lowercased() else { return 0 }
        let patterns = [
            "credits?\\s*[:\\-]?\\s*(\\d{1,2})",
            "(\\d{1,2})\\s*credits?",
            "credit\\s*hours?\\s*[:\\-]?\\s*(\\d{1,2})"
        ]
        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let match = re.firstMatch(in: desc, range: NSRange(desc.startIndex..., in: desc)),
                  match.numberOfRanges >= 2,
                  let range = Range(match.range(at: 1), in: desc),
                  let value = Int(desc[range]), value > 0 else { continue }
            return value
        }
        return 0
    }
}