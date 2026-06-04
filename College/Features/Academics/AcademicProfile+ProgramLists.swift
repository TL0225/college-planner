// AcademicProfile+ProgramLists.swift
// Feature: Academics
// Purpose: Academics module — AcademicProfileProgramLists.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum AcademicProfileProgramLists {}

extension AcademicProfileProgramLists {
    static func majors(from profile: AcademicProfile) -> [String] {
        if let csv = profile.majorsCSV, !csv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let decoded = ProgramListSerialization.coalesceProgramList(ProgramListSerialization.decode(csv))
            if !decoded.isEmpty { return decoded }
        }
        return ProgramListSerialization.majorsFromLegacyProfile(
            major: profile.major,
            secondaryMajor: profile.secondaryMajor
        )
    }

    static func minors(from profile: AcademicProfile) -> [String] {
        if let csv = profile.minorsCSV, !csv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let decoded = ProgramListSerialization.coalesceProgramList(ProgramListSerialization.decode(csv))
            if !decoded.isEmpty { return decoded }
        }
        return ProgramListSerialization.coalesceProgramList(ProgramListSerialization.decode(profile.minor))
    }

    static func syncToProfile(majors: [String], minors: [String], profile: AcademicProfile) {
        let cleanedMajors = majors.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let cleanedMinors = minors.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let majorsToStore = ProgramListSerialization.coalesceProgramList(cleanedMajors)
        let minorsToStore = ProgramListSerialization.coalesceProgramList(cleanedMinors)
        profile.majorsCSV = ProgramListSerialization.encode(majorsToStore)
        profile.minorsCSV = ProgramListSerialization.encode(minorsToStore)
        profile.major = majorsToStore.first
        profile.secondaryMajor = majorsToStore.count > 1 ? majorsToStore[1] : nil
        profile.minor = minorsToStore.isEmpty ? nil : minorsToStore.joined(separator: ", ")
    }
}
