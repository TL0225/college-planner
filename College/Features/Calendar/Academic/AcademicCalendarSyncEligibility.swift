// AcademicCalendarSyncEligibility.swift
// Feature: Calendar
// Purpose: Gate automatic academic calendar sync until school, major, and skeleton catalog are ready.

import Foundation

@MainActor
enum AcademicCalendarSyncEligibility {
    struct Gate: Equatable, Sendable {
        var activeSchoolSelected: Bool
        var majorEntered: Bool
        var skeletonSyncCompleted: Bool

        var isReady: Bool {
            activeSchoolSelected && majorEntered && skeletonSyncCompleted
        }
    }

    static func gate(persistence: CollegePersistence) -> Gate {
        let universityName = persistence.getActiveUniversityName()?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let activeSchoolSelected = !universityName.isEmpty
        let majorEntered = hasMajorEntered(persistence: persistence)
        let skeletonSyncCompleted = activeSchoolSelected
            && persistence.catalogCapabilitiesSync(universityName: universityName).programsReady
        return Gate(
            activeSchoolSelected: activeSchoolSelected,
            majorEntered: majorEntered,
            skeletonSyncCompleted: skeletonSyncCompleted
        )
    }

    static func activeSchoolID(persistence: CollegePersistence) -> String? {
        guard let name = persistence.getActiveUniversityName()?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !name.isEmpty else {
            return nil
        }
        let schools = SchoolManifestCatalog.bundled()
        let manifest = schools.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })
        return manifest?.id ?? name.lowercased().replacingOccurrences(of: " ", with: "_")
    }

    static func isEligible(config: AcademicCalendarConfig, persistence: CollegePersistence) -> Bool {
        guard gate(persistence: persistence).isReady,
              let activeSchoolID = activeSchoolID(persistence: persistence),
              config.schoolID.caseInsensitiveCompare(activeSchoolID) == .orderedSame else {
            return false
        }
        return true
    }

    static func eligibleConfigs(persistence: CollegePersistence) -> [AcademicCalendarConfig] {
        AcademicCalendarStore.loadAllConfigs().filter { isEligible(config: $0, persistence: persistence) }
    }

    private static func hasMajorEntered(persistence: CollegePersistence) -> Bool {
        if let profile = persistence.primaryAcademicProfile {
            if !AcademicProfileProgramLists.majors(from: profile).isEmpty {
                return true
            }
            if let legacyMajor = profile.major?.trimmingCharacters(in: .whitespacesAndNewlines),
               !legacyMajor.isEmpty {
                return true
            }
        }
        return !persistence.resolvedMajorNames().isEmpty
    }
}
