// CollegePersistence+AcademicProgress.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CollegePersistence+AcademicProgress.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// Academic progress entry points (Phase 7f — implementations in `CollegePersistence+AcademicComputation`).
@MainActor
extension CollegePersistence {
    func resolvedMajorNames(for academicProfile: AcademicProfile) -> [String] {
        AcademicProfileProgramLists.majors(from: academicProfile)
    }

    func resolvedMinorNames(for academicProfile: AcademicProfile) -> [String] {
        AcademicProfileProgramLists.minors(from: academicProfile)
    }

    func academicProfile(id: UUID) -> AcademicProfile? {
        try? profileRepository.fetchAcademicProfile(id: id)
    }
}