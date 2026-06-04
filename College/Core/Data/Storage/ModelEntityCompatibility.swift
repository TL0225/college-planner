// ModelEntityCompatibility.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — ModelEntityCompatibility.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

// MARK: - Legacy local store entity name aliases (Phase 7f)

typealias DegreeRequirementEntity = CatalogDegreeRequirement
typealias CourseEntity = PlannerCourse
typealias SemesterEntity = PlannerSemester
typealias PlanEntity = PlannerPlan
typealias CourseCatalogEntity = CourseCatalog
typealias VaultDocumentEntity = VaultDocument
typealias WorkdayJobPostingEntity = WorkdayJobPosting
typealias CalendarEventEntity = CalendarEvent
typealias AcademicProfileEntity = AcademicProfile
typealias ProfileEntity = Profile
typealias CourseOverrideEntity = CourseOverride

// MARK: - Legacy NSObject-style identifiers

@MainActor
extension PlannerCourse {
    var objectID: UUID { id }

    var catalogCourse: CourseCatalog? {
        guard let catalogCourseID else { return nil }
        return try? AppDataStore.shared.catalogRepository?.fetchCatalogCourse(id: catalogCourseID)
    }

    var professorEmail: String? { nil }
    var professorContactMethod: String? { nil }
    var professorOfficeHours: String? { nil }
    var syllabusFileName: String? { nil }
}

@MainActor
extension CourseOverride {
    var professorEmail: String? { professor }
    var professorContactMethod: String? { nil }
    var professorOfficeHours: String? { nil }
}

@MainActor
extension AcademicProfile {
    var objectID: UUID { id }
}

extension JobApplication {
    var objectID: UUID { id }

    /// Legacy local store field name; stored in `jobDescriptionText`.
    var jobDescriptionHTML: String? {
        get { jobDescriptionText }
        set { jobDescriptionText = newValue }
    }
}

extension CareerEvent {
    var objectID: UUID { id }
}

extension Profile {
    var displayName: String {
        (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension CourseCatalog {
    var prerequisiteCodes: [String] {
        Self.parseCourseCodes(from: prerequisiteText)
    }

    var corequisiteCodes: [String] {
        Self.parseCourseCodes(from: prerequisiteRulesJSON)
    }

    private static func parseCourseCodes(from raw: String?) -> [String] {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let pattern = #"[A-Z]{2,5}\s*\d{3,4}[A-Z]?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        return regex.matches(in: raw, range: range).compactMap { match in
            guard let r = Range(match.range, in: raw) else { return nil }
            return String(raw[r]).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        }
    }
}