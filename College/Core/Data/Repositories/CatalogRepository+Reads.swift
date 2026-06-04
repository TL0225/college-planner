// CatalogRepository+Reads.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CatalogRepository+Reads.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension CatalogRepository {
    func hasPrograms(universityID: UUID) throws -> Bool {
        var descriptor = FetchDescriptor<Major>(
            predicate: #Predicate { major in
                major.university?.id == universityID
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first != nil
    }

    func fetchAllMajors(universityID: UUID, limit: Int = 5_000) throws -> [Major] {
        var descriptor = FetchDescriptor<Major>(
            predicate: #Predicate { major in
                major.university?.id == universityID
            },
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        descriptor.fetchLimit = max(1, limit)
        return try context.fetch(descriptor)
    }

    func fetchDepartments(universityID: UUID, limit: Int = 2_000) throws -> [Department] {
        var descriptor = FetchDescriptor<Department>(
            predicate: #Predicate { department in
                department.university?.id == universityID
            },
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        descriptor.fetchLimit = max(1, limit)
        return try context.fetch(descriptor)
    }

    func fetchCatalogCourseCount(universityID: UUID) throws -> Int {
        try context.fetchCount(
            FetchDescriptor<CourseCatalog>(
                predicate: #Predicate { course in
                    course.university?.id == universityID && course.isArchived == false
                }
            )
        )
    }

    func fetchDegreeRequirementCount(universityID: UUID) throws -> Int {
        try context.fetchCount(
            FetchDescriptor<CatalogDegreeRequirement>(
                predicate: #Predicate { requirement in
                    requirement.university?.id == universityID
                }
            )
        )
    }

    func fetchDegreeRequirements(universityID: UUID, limit: Int = 10_000) throws -> [CatalogDegreeRequirement] {
        var descriptor = FetchDescriptor<CatalogDegreeRequirement>(
            predicate: #Predicate { requirement in
                requirement.university?.id == universityID
            },
            sortBy: [SortDescriptor(\.sectionOrder, order: .forward)]
        )
        descriptor.fetchLimit = max(1, limit)
        return try context.fetch(descriptor)
    }

    func fetchScrapeStates(universityID: UUID) throws -> [CatalogScrapeState] {
        var descriptor = FetchDescriptor<CatalogScrapeState>(
            predicate: #Predicate { state in
                state.university?.id == universityID
            },
            sortBy: [SortDescriptor(\.catoid, order: .forward)]
        )
        descriptor.fetchLimit = 500
        return try context.fetch(descriptor)
    }

    func fetchAllCatalogCourses(universityID: UUID, limit: Int = 50_000) throws -> [CourseCatalog] {
        try fetchCatalogCoursesPage(
            universityID: universityID,
            offset: 0,
            limit: limit,
            includeArchived: true
        )
    }
}