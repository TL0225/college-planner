// AcademicProfileIdentityTests.swift
// Feature: Profile
// Purpose: ensurePrimaryAcademicProfile is idempotent and prunes empty duplicates.

import SwiftData
import XCTest
@testable import College

@MainActor
final class AcademicProfileIdentityTests: PersistenceTestCase {
    private var persistence: CollegePersistence { .shared }

    override func setUpWithError() throws {
        try super.setUpWithError()
        for academic in try profileContext.fetch(FetchDescriptor<AcademicProfile>()) {
            profileContext.delete(academic)
        }
        for profile in try profileContext.fetch(FetchDescriptor<Profile>()) {
            profileContext.delete(profile)
        }
        try profileContext.save()
        persistence.refreshAll()
    }

    func testEnsurePrimaryAcademicProfile_isIdempotentWhenCacheIsEmpty() throws {
        _ = persistence.ensurePrimaryProfile()
        persistence.academicProfiles = []

        XCTAssertNotNil(persistence.ensurePrimaryAcademicProfile())
        XCTAssertNotNil(persistence.ensurePrimaryAcademicProfile())
        XCTAssertNotNil(persistence.ensurePrimaryAcademicProfile())

        let stored = try persistence.profileRepository.fetchAcademicProfiles()
        XCTAssertEqual(stored.count, 1)
    }

    func testPruneDuplicateEmptyAcademicProfiles_keepsDeclaredProgram() throws {
        let shell = try persistence.profileRepository.ensurePrimaryProfileShell()
        let keeper = AcademicProfile(sortOrder: 0, isPrimary: true, isActive: true, status: AcademicProfileStatus.active.rawValue)
        keeper.profile = shell
        keeper.majorsCSV = "Cyber Defense, MS"
        keeper.degreeType = "Master of Science (MS)"
        profileContext.insert(keeper)

        for index in 1...3 {
            let empty = AcademicProfile(
                sortOrder: Int16(index),
                isPrimary: false,
                isActive: true,
                status: AcademicProfileStatus.active.rawValue
            )
            empty.profile = shell
            profileContext.insert(empty)
        }
        try profileContext.save()
        persistence.refreshAll()

        persistence.pruneDuplicateEmptyAcademicProfiles()

        let stored = try persistence.profileRepository.fetchAcademicProfiles()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.degreeType, "Master of Science (MS)")
        XCTAssertTrue(stored.first?.isPrimary == true)
    }
}
