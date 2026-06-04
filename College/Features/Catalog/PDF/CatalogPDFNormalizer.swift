// CatalogPDFNormalizer.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogPDFNormalizer.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Stage 5: canonicalize recognized entities (no re-classification).
enum CatalogPDFNormalizer {
    static func normalizePrograms(
        _ programs: [ScrapedProgram],
        schoolID: String
    ) -> [ScrapedProgram] {
        programs.map { program in
            let urlTrimmed = program.url.trimmingCharacters(in: .whitespacesAndNewlines)
            let syntheticURL: String = {
                let normalized = program.name
                    .lowercased()
                    .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
                let safe = normalized.isEmpty ? "program" : normalized
                return "pdf://v1/\(schoolID)/program/\(safe)"
            }()

            let degreeTypeTrimmed = program.degreeType?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            let degreeType = (degreeTypeTrimmed?.isEmpty ?? true) ? nil : degreeTypeTrimmed

            return ScrapedProgram(
                name: program.name.trimmingCharacters(in: .whitespacesAndNewlines),
                type: program.type,
                url: urlTrimmed.isEmpty ? syntheticURL : urlTrimmed,
                group: program.group,
                department: program.department?.trimmingCharacters(in: .whitespacesAndNewlines),
                college: program.college,
                degreeType: degreeType,
                requirements: program.requirements
            )
        }
    }

    static func normalizeCourses(_ courses: [CatalogCourse]) -> [CatalogCourse] {
        courses.map { course in
            let code = course.courseCode
                .uppercased()
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return CatalogCourse(
                courseCode: code,
                title: course.title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: course.description,
                credits: max(0, course.credits),
                department: course.department?.trimmingCharacters(in: .whitespacesAndNewlines),
                prerequisites: course.prerequisites,
                prerequisiteText: course.prerequisiteText,
                corequisites: course.corequisites,
                typicallyOffered: course.typicallyOffered
            )
        }
    }
}
