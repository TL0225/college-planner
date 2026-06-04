// CatalogRepository+ScrapePurge.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CatalogScrapePurgeCounts.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension CatalogRepository {
    struct CatalogScrapePurgeCounts: Sendable, Equatable {
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
    }

    func purgeCatalogScrapeData(
        forUniversityName universityName: String,
        programURLContains programURLNeedle: String?
    ) throws -> CatalogScrapePurgeCounts {
        var counts = CatalogScrapePurgeCounts()
        guard let university = try fetchUniversity(named: universityName) else {
            return counts
        }

        let universityID = university.id
        let needle = programURLNeedle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        func deleteMatching<T: PersistentModel>(_ rows: [T]) {
            for row in rows {
                context.delete(row)
            }
        }

        let courses = try context.fetch(
            FetchDescriptor<CourseCatalog>(
                predicate: #Predicate { $0.university?.id == universityID }
            )
        )
        counts.catalogCourses = courses.count
        deleteMatching(courses)

        let departments = try context.fetch(
            FetchDescriptor<Department>(
                predicate: #Predicate { $0.university?.id == universityID }
            )
        )
        counts.departments = departments.count
        deleteMatching(departments)

        let scrapeStates = try context.fetch(
            FetchDescriptor<CatalogScrapeState>(
                predicate: #Predicate { $0.university?.id == universityID }
            )
        )
        counts.scrapeStates = scrapeStates.count
        deleteMatching(scrapeStates)

        let policyDocuments = try context.fetch(
            FetchDescriptor<CatalogPolicyDocument>(
                predicate: #Predicate { $0.university?.id == universityID }
            )
        )
        counts.policyDocuments = policyDocuments.count
        deleteMatching(policyDocuments)

        let majors: [Major]
        if let needle {
            let lowerNeedle = needle.lowercased()
            majors = try fetchAllMajors(universityID: universityID).filter { major in
                guard let url = major.programURL?.lowercased(), !url.isEmpty else { return false }
                return url.contains(lowerNeedle)
            }
        } else {
            majors = try fetchAllMajors(universityID: universityID)
        }
        counts.majors = majors.count
        deleteMatching(majors)

        let majorNames = Set(majors.map(\.name))
        let degreeRequirements = try fetchDegreeRequirements(universityID: universityID, limit: 50_000)
            .filter { needle == nil || majorNames.contains($0.major) }
        counts.degreeRequirements = degreeRequirements.count
        deleteMatching(degreeRequirements)

        let fulfillmentDescriptor = FetchDescriptor<RequirementFulfillment>(
            predicate: #Predicate { row in
                row.university == universityName
            }
        )
        let fulfillments = try context.fetch(fulfillmentDescriptor).filter { row in
            guard let needle else { return true }
            return row.programURL.lowercased().contains(needle.lowercased())
        }
        counts.requirementFulfillments = fulfillments.count
        deleteMatching(fulfillments)

        try context.save()
        return counts
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}