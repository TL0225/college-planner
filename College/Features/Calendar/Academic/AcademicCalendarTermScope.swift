// AcademicCalendarTermScope.swift
// Feature: Calendar
// Purpose: Resolve the app's active planner term for academic calendar imports.

import Foundation

enum AcademicCalendarTermScope {
    struct Resolved: Sendable, Equatable {
        var term: String
        var year: Int
        var label: String
        var level: AcademicCalendarLevelScope

        var importedScope: AcademicCalendarImportedScope {
            AcademicCalendarImportedScope(term: term, year: year, level: level)
        }
    }

    @MainActor
    static func resolve(
        persistence: CollegePersistence,
        level: AcademicCalendarLevelScope = .all
    ) -> Resolved? {
        let plan = persistence.getActivePlan()
        let semesters = plan?.semestersArray.isEmpty == false
            ? (plan?.semestersArray ?? [])
            : persistence.semesters
        guard let semester = AcademicTermResolver.resolveCurrentSemester(from: semesters) else {
            return nil
        }
        let season = semester.season.trimmingCharacters(in: .whitespacesAndNewlines)
        let year = Int(semester.year)
        guard !season.isEmpty, year > 0 else { return nil }
        let term = season.capitalized
        return Resolved(term: term, year: year, label: "\(term) \(year)", level: level)
    }

    @MainActor
    static func importedScopes(
        persistence: CollegePersistence,
        level: AcademicCalendarLevelScope
    ) -> [AcademicCalendarImportedScope] {
        guard let resolved = resolve(persistence: persistence, level: level) else { return [] }
        return [resolved.importedScope]
    }
}
