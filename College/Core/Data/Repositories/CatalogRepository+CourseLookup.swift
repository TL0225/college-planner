// CatalogRepository+CourseLookup.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CatalogRepository+CourseLookup.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension CatalogRepository {
    func fetchCatalogCourse(universityID: UUID, code: String) throws -> CourseCatalog? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var descriptor = FetchDescriptor<CourseCatalog>(
            predicate: #Predicate { course in
                course.university?.id == universityID && course.courseCode == trimmed
            }
        )
        descriptor.fetchLimit = 50
        let matches = try context.fetch(descriptor)
        if matches.isEmpty { return nil }
        if matches.count == 1 { return matches[0] }
        return matches.max(by: { catalogCourseQualityScore($0) < catalogCourseQualityScore($1) })
    }

    func fetchCatalogCourseMatching(universityID: UUID, code raw: String) throws -> CourseCatalog? {
        var seen = Set<String>()
        for candidate in CatalogImportTransforms.catalogLookupCandidates(for: raw) {
            guard seen.insert(candidate).inserted else { continue }
            if let course = try fetchCatalogCourse(universityID: universityID, code: candidate) {
                return course
            }
        }
        return nil
    }

    func fetchCatalogCoursesMatchingBatch(
        universityID: UUID,
        codes rawCodes: [String]
    ) throws -> [String: CourseCatalog] {
        try AuditCatalogBatchLookupQuery.matchingBatch(
            universityID: universityID,
            codes: rawCodes,
            context: context
        )
    }

    private func catalogCourseQualityScore(_ course: CourseCatalog) -> Int {
        let title = course.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = course.courseCode.trimmingCharacters(in: .whitespacesAndNewlines)
        var score = 0
        if course.credits > 0 { score += 3 }
        if !title.isEmpty && title.uppercased() != code.uppercased() { score += 2 }
        if let desc = course.descriptionText, !desc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            score += 1
        }
        return score
    }
}