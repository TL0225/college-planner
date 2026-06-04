// ProfileRepository+ProfileShellWrites.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — ProfileRepository+ProfileShellWrites.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension ProfileRepository {
    /// Inserts a primary `Profile` shell when the store has none (e.g. post-migration edge cases).
    func ensurePrimaryProfileShell() throws -> Profile {
        if let existing = try fetchPrimaryProfile() {
            return existing
        }
        let profile = Profile(name: nil)
        context.insert(profile)
        ModelMergeCoalescer.scheduleSave(context)
        return profile
    }

    @discardableResult
    func createAcademicProfile(
        degreeLevel: String,
        collegeName: String?,
        linkExistingPlan: Bool
    ) throws -> AcademicProfile? {
        guard let shell = try fetchPrimaryProfile() else { return nil }
        let order = Int16((try? fetchAcademicProfiles().count) ?? 0)
        let academic = AcademicProfile(
            sortOrder: order,
            isPrimary: order == 0,
            isActive: true,
            status: AcademicProfileStatus.active.rawValue,
            accentColorIndex: Int16(Int(order) % AcademicProfilePresentation.accentPalette.count)
        )
        academic.degreeLevel = degreeLevel
        academic.collegeName = collegeName ?? shell.collegeName
        academic.profile = shell
        if linkExistingPlan, let plan = try fetchPlans(limit: 1).first {
            academic.plan = plan
        }
        context.insert(academic)
        ModelMergeCoalescer.scheduleSave(context)
        return academic
    }

    func updateProfileShell(
        id: UUID,
        name: String?,
        pronouns: String?,
        universityEmail: String?,
        personalPhone: String?,
        permanentAddress: String?,
        advisorName: String?,
        studentId: String?,
        profilePhotoData: Data?
    ) throws {
        guard let profile = try fetchProfile(id: id) else { return }
        profile.name = name
        profile.pronouns = pronouns
        profile.universityEmail = universityEmail
        profile.personalPhone = personalPhone
        profile.permanentAddress = permanentAddress
        profile.advisorName = advisorName
        profile.studentId = studentId
        profile.profilePhotoData = profilePhotoData
        ModelMergeCoalescer.scheduleSave(context)
    }
}