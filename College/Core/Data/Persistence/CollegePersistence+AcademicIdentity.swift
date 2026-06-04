// CollegePersistence+AcademicIdentity.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CollegePersistence+AcademicIdentity.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension CollegePersistence {
    var primaryAcademicProfile: AcademicProfile? {
        academicProfiles.first(where: \.isPrimary) ?? academicProfiles.first
    }

    @discardableResult
    func ensurePrimaryAcademicProfile(linkExistingPlan: Bool = true) -> AcademicProfile? {
        if let existing = primaryAcademicProfile { return existing }
        guard profile != nil else { return nil }
        return try? profileRepository.createAcademicProfile(
            degreeLevel: DegreeConfiguration.undergraduate,
            collegeName: profile?.collegeName,
            linkExistingPlan: linkExistingPlan
        )
    }

    func primaryDegreeType() -> String? {
        let fromPrimary = primaryAcademicProfile?.degreeType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return fromPrimary.isEmpty ? nil : fromPrimary
    }

    func primaryMajorDisplay() -> String? {
        resolvedMajorNames().first
    }

    func primarySecondaryMajorDisplay() -> String? {
        let majors = resolvedMajorNames()
        return majors.count > 1 ? majors[1] : nil
    }

    func primaryMinorDisplay() -> String? {
        resolvedMinorNames().first
    }

    func primaryDepartment() -> String? {
        primaryAcademicProfile?.department
    }

    func primaryClassStanding() -> String? {
        primaryAcademicProfile?.classStanding
    }

    func primaryExpectedGraduation() -> String? {
        primaryAcademicProfile?.expectedGraduation
    }

    func primaryGPA() -> Double {
        primaryAcademicProfile?.gpa ?? 0
    }

    func primaryCreditsEarned() -> Int {
        Int(primaryAcademicProfile?.creditsEarned ?? 0)
    }

    func primaryCreditsRequired() -> Int {
        Int(primaryAcademicProfile?.creditsRequired ?? 0)
    }

    func primaryTransferGPA() -> Double {
        primaryAcademicProfile?.transferGpa ?? 0
    }

    func setPrimaryDegreeLevel(_ value: String?) {
        guard let primary = ensurePrimaryAcademicProfile() else { return }
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        primary.degreeLevel = trimmed.isEmpty ? nil : trimmed
        save()
    }

    func setPrimaryDegreeType(_ value: String?) {
        guard let primary = ensurePrimaryAcademicProfile() else { return }
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        primary.degreeType = trimmed.isEmpty ? nil : trimmed
        save()
    }

    func setPrimaryDepartment(_ value: String?) {
        guard let primary = ensurePrimaryAcademicProfile() else { return }
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        primary.department = trimmed.isEmpty ? nil : trimmed
        save()
    }

    func setPrimaryClassStanding(_ value: String?) {
        guard let primary = ensurePrimaryAcademicProfile() else { return }
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        primary.classStanding = trimmed.isEmpty ? nil : trimmed
        save()
    }

    func setPrimaryExpectedGraduation(_ value: String?) {
        guard let primary = ensurePrimaryAcademicProfile() else { return }
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        primary.expectedGraduation = trimmed.isEmpty ? nil : trimmed
        save()
    }

    func setPrimaryGPA(_ value: Double) {
        ensurePrimaryAcademicProfile()?.gpa = value
        save()
    }

    func setPrimaryCreditsEarned(_ value: Int) {
        ensurePrimaryAcademicProfile()?.creditsEarned = Int32(value)
        save()
    }

    func setPrimaryTransferGPA(_ value: Double) {
        ensurePrimaryAcademicProfile()?.transferGpa = value
        save()
    }

    func setPrimarySecondaryMajor(_ value: String?) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var majors = resolvedMajorNames()
        if majors.isEmpty {
            majors = trimmed.isEmpty ? [] : [trimmed]
        } else if trimmed.isEmpty {
            majors = [majors[0]]
        } else {
            majors = [majors[0], trimmed]
        }
        syncPrimaryPrograms(majors: majors, minors: resolvedMinorNames())
    }

    func setPrimaryMinor(_ value: String?) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let minors = trimmed.isEmpty ? [] : [trimmed]
        syncPrimaryPrograms(majors: resolvedMajorNames(), minors: minors)
    }

    func syncPrimaryPrograms(majors: [String], minors: [String]) {
        guard let primary = ensurePrimaryAcademicProfile() else { return }
        AcademicProfileProgramLists.syncToProfile(majors: majors, minors: minors, profile: primary)
        save()
    }

    func clearPrimaryDeclaredPrograms() {
        syncPrimaryPrograms(majors: [], minors: resolvedMinorNames())
    }

    func commitPrimaryAcademicProfileEdits() {
        _ = try? appDataStore.profileSave()
        fetchAcademicProfiles()
        bumpProfileRevision()
    }

    @discardableResult
    func addAcademicProfile(
        degreeLevel: String,
        collegeName: String? = nil,
        linkExistingPlan: Bool = false
    ) -> AcademicProfile? {
        let created = try? profileRepository.createAcademicProfile(
            degreeLevel: degreeLevel,
            collegeName: collegeName ?? profile?.collegeName,
            linkExistingPlan: linkExistingPlan
        )
        fetchAcademicProfiles()
        bumpProfileRevision()
        return created
    }

    func reorderAcademicProfiles(_ ordered: [AcademicProfile]) {
        for (index, profile) in ordered.enumerated() {
            profile.sortOrder = Int16(index)
        }
        save()
        fetchAcademicProfiles()
        bumpProfileRevision()
    }

    /// local store-only profile commit (Phase 7f).
    func commitProfileEdits(reconcileSnapshot: Bool = false) {
        _ = reconcileSnapshot
        save()
        bumpProfileRevision()
    }
}