// CatalogIngestParityDiff.swift
// Feature: Catalog
// Purpose: Dev helper — compare legacy crawl vs IR entity sets for offline fixtures.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CatalogIngestParityDiff {
    struct EntitySetSummary: Sendable, Equatable {
        let courseCodes: Set<String>
        let programURLs: Set<String>
        let programNames: Set<String>
    }

    struct DiffReport: Sendable, Equatable {
        let schoolID: String
        let legacy: EntitySetSummary
        let ir: EntitySetSummary
        let coursesOnlyInLegacy: Set<String>
        let coursesOnlyInIR: Set<String>
        let programsOnlyInLegacy: Set<String>
        let programsOnlyInIR: Set<String>

        var isParity: Bool {
            coursesOnlyInLegacy.isEmpty
                && coursesOnlyInIR.isEmpty
                && programsOnlyInLegacy.isEmpty
                && programsOnlyInIR.isEmpty
        }
    }

    static func compareFixture(
        xml: String,
        pageURL: URL,
        schoolID: String
    ) -> DiffReport {
        let legacyCourses = CourseLeafEngine.parseCatalogPageLegacy(
            xml: xml,
            pageURL: pageURL,
            schoolID: schoolID
        )
        let ir = CourseLeafEngine.parseCatalogPage(xml: xml, pageURL: pageURL, schoolID: schoolID)

        let legacySummary = EntitySetSummary(
            courseCodes: Set(legacyCourses.courses.map { CatalogImportTransforms.normalizeCourseCode($0.courseCode) }),
            programURLs: Set(legacyCourses.programs.map(\.url)),
            programNames: Set(legacyCourses.programs.map(\.name))
        )
        let irSummary = EntitySetSummary(
            courseCodes: Set(ir.courses.map { CatalogImportTransforms.normalizeCourseCode($0.courseCode) }),
            programURLs: Set(ir.programs.map(\.url)),
            programNames: Set(ir.programs.map(\.name))
        )

        return DiffReport(
            schoolID: schoolID,
            legacy: legacySummary,
            ir: irSummary,
            coursesOnlyInLegacy: legacySummary.courseCodes.subtracting(irSummary.courseCodes),
            coursesOnlyInIR: irSummary.courseCodes.subtracting(legacySummary.courseCodes),
            programsOnlyInLegacy: legacySummary.programURLs.subtracting(irSummary.programURLs),
            programsOnlyInIR: irSummary.programURLs.subtracting(legacySummary.programURLs)
        )
    }
}
