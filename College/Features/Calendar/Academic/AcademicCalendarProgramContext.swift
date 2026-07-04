// AcademicCalendarProgramContext.swift
// Feature: Calendar
// Purpose: Resolve undergraduate vs graduate calendar audience from the active program catalog.

import Foundation

@MainActor
enum AcademicCalendarProgramContext {
    struct Resolved: Sendable, Equatable {
        var degreeLevel: String
        var levelScope: AcademicCalendarLevelScope
        var programLabel: String?
        var owningCollege: String?
        var owningDepartment: String?
        var isDegraded: Bool

        var audienceLabel: String {
            switch levelScope {
            case .undergrad:
                return String(localized: "settings.calendar.audience_undergrad", defaultValue: "Undergraduate")
            case .grad:
                return String(localized: "settings.calendar.audience_grad", defaultValue: "Graduate")
            case .all:
                return String(localized: "settings.calendar.audience_all", defaultValue: "All")
            }
        }
    }

    static func resolve(persistence: CollegePersistence) -> Resolved? {
        let profile = persistence.academicProfiles.first(where: \.isPrimary)
            ?? persistence.academicProfiles.first
        let majors = profile.map { AcademicProfileProgramLists.majors(from: $0) } ?? []
        let programLabel = majors.first?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let inference = DeclaredProgramDegreeMetadata.effectiveMetadata(
            majors: majors,
            storedDegreeType: profile?.degreeType,
            storedDegreeLevel: profile?.degreeLevel,
            catalogFallback: nil
        ) {
            return resolved(degreeLevel: inference.degreeLevel, programLabel: programLabel)
        }

        let storedLevel = persistence.primaryDegreeLevel(default: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !storedLevel.isEmpty else { return nil }
        return resolved(degreeLevel: storedLevel, programLabel: programLabel)
    }

    static func levelScope(for persistence: CollegePersistence, fallback: AcademicCalendarLevelScope = .all) -> AcademicCalendarLevelScope {
        resolve(persistence: persistence)?.levelScope ?? fallback
    }

    static func degreeLevel(for persistence: CollegePersistence) -> String? {
        resolve(persistence: persistence)?.degreeLevel
    }

    private static func resolved(degreeLevel: String, programLabel: String?) -> Resolved {
        let scope: AcademicCalendarLevelScope = DegreeConfiguration.isUndergraduate(degreeLevel) ? .undergrad : .grad
        return Resolved(degreeLevel: degreeLevel, levelScope: scope, programLabel: programLabel, owningCollege: nil, owningDepartment: nil, isDegraded: true)
    }

    static func programProfile(persistence: CollegePersistence) -> AcademicCalendarProgramProfile? {
        AcademicCalendarProgramProfile.resolve(persistence: persistence)
    }
}
