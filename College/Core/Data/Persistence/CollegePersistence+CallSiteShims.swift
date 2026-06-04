// CollegePersistence+CallSiteShims.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — ScrapeCoverageReport.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

// MARK: - Legacy call-site forwards (Phase 7f)

@MainActor
extension CollegePersistence {
    struct ScrapeCoverageReport: Sendable {
        var totalCourses: Int = 0
        var coursesByCatoid: [String: Int] = [:]
        var programsByCatoid: [String: Int] = [:]
        var requirementsByCatoid: [String: Int] = [:]
    }

    func fetchMinors(for universityName: String, degreeLevel: String) -> [String] {
        CatalogProgramReadBridge.fetchMinors(
            for: universityName,
            degreeLevel: degreeLevel,
            appDataStore: appDataStore
        )
    }

    func resolveSelectedMajorProgramURL() -> String? {
        guard let profile = profile ?? (try? profileRepository.fetchPrimaryProfile()) else { return nil }
        let majors = resolvedMajorNames()
        guard let major = majors.first?.trimmingCharacters(in: .whitespacesAndNewlines), !major.isEmpty else {
            return nil
        }
        let university = profile.collegeName ?? getActiveUniversityName() ?? ""
        return resolveProgramURL(
            programDisplay: major,
            universityName: university,
            degreeLevel: "Undergraduate",
            degreeType: nil,
            isMinor: false
        )
    }

    func scrapeCoverage(universityName: String, catoids: [String]) async -> ScrapeCoverageReport {
        var report = ScrapeCoverageReport()
        guard let repo = catalogRepository,
              let university = try? repo.fetchUniversity(named: universityName) else {
            return report
        }
        report.totalCourses = (try? repo.fetchCatalogCourseCount(universityID: university.id)) ?? 0
        for catoid in catoids {
            let needle = catoid.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !needle.isEmpty else { continue }
            let presence = catalogScrapeDataPresence(
                forUniversityName: universityName,
                programURLContains: needle
            )
            report.coursesByCatoid[needle] = presence.catalogCourses
            report.programsByCatoid[needle] = presence.majors
            report.requirementsByCatoid[needle] = presence.degreeRequirements
        }
        return report
    }

    func shouldForceCourseRescrapeForSubject(
        universityName: String,
        subjectCode: String,
        catoid: String? = nil
    ) -> Bool {
        _ = universityName
        _ = subjectCode
        _ = catoid
        return false
    }

    func shouldForceCourseRescrapeForSubject(
        universityName: String,
        subjectPrefix: String
    ) -> Bool {
        shouldForceCourseRescrapeForSubject(
            universityName: universityName,
            subjectCode: subjectPrefix,
            catoid: nil
        )
    }

    func resolveNonMinorMajorProgramURL(display: String) -> String? {
        let university = getActiveUniversityName() ?? ""
        return resolveProgramURL(
            programDisplay: display,
            universityName: university,
            degreeLevel: "Undergraduate",
            degreeType: nil,
            isMinor: false
        )
    }

    func exportScrapedCatalogCSVFromExistingStore(for universityName: String) async throws -> URL {
        _ = universityName
        throw NSError(
            domain: "CollegePersistence",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Catalog CSV export is not available in the local store build yet."]
        )
    }

    func debugExportProgramsTSV(for universityName: String) -> URL? {
        _ = universityName
        return nil
    }

    func debugOtherDepartmentSources(for universityName: String) -> [String: [String]] {
        _ = universityName
        return [:]
    }

    func applyPolicyCorrection(
        universityName: String,
        policyName: String,
        correctedValue: String
    ) throws {
        _ = universityName
        guard let policies = activeSchoolPolicies() else {
            throw NSError(
                domain: "CollegePersistence",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No active school policies to update."]
            )
        }
        let key = policyName.lowercased().replacingOccurrences(of: " ", with: "")
        let updated = SchoolPolicies(
            transferCreditLimit: policies.transferCreditLimit,
            minorTransferLimit: policies.minorTransferLimit,
            maxCreditsPerSemester: key.contains("maxcredit")
                ? Int(correctedValue) ?? policies.maxCreditsPerSemester
                : policies.maxCreditsPerSemester,
            minCreditsForFullTime: policies.minCreditsForFullTime,
            gradeForCredit: key.contains("grade") ? correctedValue : policies.gradeForCredit,
            repeatCoursePolicy: policies.repeatCoursePolicy
        )
        if let encoded = try? JSONEncoder().encode(updated),
           let university = getActiveUniversity() {
            var dataByUniversity = UserDefaults.standard.dictionary(forKey: "persistence.university.schoolPolicies.v1") as? [String: Data] ?? [:]
            dataByUniversity[university.id.uuidString] = encoded
            UserDefaults.standard.set(dataByUniversity, forKey: "persistence.university.schoolPolicies.v1")
        }
        bumpCatalogDataRevision()
    }

    func cleanedProgramNameFromDisplay(_ display: String) -> String {
        AcademicProgramHelpers.cleanedProgramNameFromDisplay(display)
    }
}

extension CareerRepository {
    func hasMirroredCareerApplicationRows() throws -> Bool {
        var descriptor = FetchDescriptor<JobApplication>()
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).isEmpty == false
    }
}