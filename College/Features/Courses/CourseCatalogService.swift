// CourseCatalogService.swift
// Feature: Courses
// Purpose: Courses module — CourseCatalogService.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// Course catalog lookup against local store-imported catalog rows.
@MainActor
class CourseCatalogService {
    private let catalogRepository: CatalogRepository?

    init(collegePersistence: CollegePersistence = .shared) {
        catalogRepository = collegePersistence.catalogRepository
    }

    func searchCourses(query: String, universityID: UUID) -> [CourseCatalog] {
        guard let catalogRepository else { return [] }
        return (try? catalogRepository.searchCatalogCourses(
            universityID: universityID,
            query: query,
            limit: 50
        )) ?? []
    }

    func getCoursePrerequisites(courseCode: String, universityID: UUID) -> [CourseCatalog] {
        guard let catalogRepository else { return [] }
        guard let course = try? catalogRepository.fetchCatalogCourse(
            universityID: universityID,
            code: courseCode
        ),
              !course.prerequisiteCodes.isEmpty
        else { return [] }

        return course.prerequisiteCodes.compactMap { code in
            try? catalogRepository.fetchCatalogCourse(universityID: universityID, code: code)
        }
    }
}
