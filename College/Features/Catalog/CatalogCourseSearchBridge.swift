// CatalogCourseSearchBridge.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogCourseSearchHit.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Normalized catalog search row for local store (Phase 7f).
struct CatalogCourseSearchHit: Equatable, Sendable {
    let id: UUID
    let courseCode: String
    let title: String
    let credits: Int16
    let descriptionText: String?
    let prerequisiteCodes: String?
}

/// local store-only interactive catalog search.
@MainActor
enum CatalogCourseSearchBridge {
    static func search(
        query: String,
        limit: Int,
        persistence: CollegePersistence = .shared,
        performBackfill: Bool = false
    ) -> [CatalogCourseSearchHit] {
        _ = performBackfill
        guard let repo = persistence.catalogRepository,
              let university = persistence.getActiveUniversity() else {
            return []
        }

        let universityID = university.id
        guard let courses = try? repo.searchCatalogCourses(
            universityID: universityID,
            query: query,
            limit: limit,
            performBackfill: false
        ) else {
            return []
        }

        return courses.map {
            CatalogCourseSearchHit(
                id: $0.id,
                courseCode: $0.courseCode,
                title: $0.title,
                credits: $0.credits,
                descriptionText: $0.descriptionText,
                prerequisiteCodes: nil
            )
        }
    }

    static func resolveToModels(
        hits: [CatalogCourseSearchHit],
        persistence: CollegePersistence = .shared
    ) -> [CourseCatalog] {
        guard let repo = persistence.catalogRepository,
              persistence.getActiveUniversity() != nil else {
            return []
        }
        var resolved: [CourseCatalog] = []
        resolved.reserveCapacity(hits.count)
        var seen = Set<UUID>()

        for hit in hits {
            if let course = try? repo.fetchCatalogCourse(id: hit.id),
               seen.insert(course.id).inserted {
                resolved.append(course)
            } else if let course = persistence.getCatalogCourseMatching(code: hit.courseCode),
                      seen.insert(course.id).inserted {
                resolved.append(course)
            }
        }
        return resolved
    }
}
