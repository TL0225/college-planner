// CatalogRepository+ScrapePresence.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CatalogScrapeDataPresence.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension CatalogRepository {
    struct CatalogScrapeDataPresence: Sendable, Equatable {
        var majors: Int = 0
        var degreeRequirements: Int = 0
        var requirementFulfillments: Int = 0
        var catalogCourses: Int = 0
        var departments: Int = 0
        var scrapeStates: Int = 0
        var policyDocuments: Int = 0

        var total: Int {
            majors + degreeRequirements + requirementFulfillments + catalogCourses
                + departments + scrapeStates + policyDocuments
        }

        var isEmpty: Bool { total == 0 }
    }

    func catalogScrapeDataPresence(
        forUniversityName universityName: String,
        programURLContains programURLNeedle: String?
    ) throws -> CatalogScrapeDataPresence {
        var presence = CatalogScrapeDataPresence()
        let needle = normalizedProgramURLNeedle(programURLNeedle)
        guard let university = try fetchUniversity(named: universityName) else {
            return presence
        }

        let universityID = university.id
        presence.catalogCourses = try context.fetchCount(
            FetchDescriptor<CourseCatalog>(
                predicate: #Predicate { $0.university?.id == universityID }
            )
        )
        presence.departments = try context.fetchCount(
            FetchDescriptor<Department>(
                predicate: #Predicate { $0.university?.id == universityID }
            )
        )
        presence.scrapeStates = try context.fetchCount(
            FetchDescriptor<CatalogScrapeState>(
                predicate: #Predicate { $0.university?.id == universityID }
            )
        )
        presence.policyDocuments = try context.fetchCount(
            FetchDescriptor<CatalogPolicyDocument>(
                predicate: #Predicate { $0.university?.id == universityID }
            )
        )

        if let needle {
            let majors = try fetchMajorsMatchingProgramURL(universityID: universityID, needle: needle)
            presence.majors = majors.count
            presence.degreeRequirements = try countDegreeRequirements(
                universityID: universityID,
                programURLNeedle: needle
            )
            presence.requirementFulfillments = try countRequirementFulfillments(
                universityName: university.name,
                programURLNeedle: needle
            )
        } else {
            presence.majors = try context.fetchCount(
                FetchDescriptor<Major>(
                    predicate: #Predicate { $0.university?.id == universityID }
                )
            )
            presence.degreeRequirements = try fetchDegreeRequirementCount(universityID: universityID)
        }

        return presence
    }

    private func normalizedProgramURLNeedle(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func fetchMajorsMatchingProgramURL(universityID: UUID, needle: String) throws -> [Major] {
        let majors = try fetchAllMajors(universityID: universityID)
        let lowerNeedle = needle.lowercased()
        return majors.filter { major in
            guard let url = major.programURL?.lowercased(), !url.isEmpty else { return false }
            return url.contains(lowerNeedle)
        }
    }

    private func countDegreeRequirements(universityID: UUID, programURLNeedle: String) throws -> Int {
        let matchingMajors = try fetchMajorsMatchingProgramURL(universityID: universityID, needle: programURLNeedle)
        let majorNames = Set(matchingMajors.map(\.name))
        guard !majorNames.isEmpty else { return 0 }
        let rows = try fetchDegreeRequirements(universityID: universityID, limit: 50_000)
        return rows.filter { majorNames.contains($0.major) }.count
    }

    private func countRequirementFulfillments(universityName: String, programURLNeedle: String) throws -> Int {
        let lowerNeedle = programURLNeedle.lowercased()
        let descriptor = FetchDescriptor<RequirementFulfillment>(
            predicate: #Predicate { row in
                row.university == universityName
            }
        )
        let rows = try context.fetch(descriptor)
        return rows.filter { $0.programURL.lowercased().contains(lowerNeedle) }.count
    }
}