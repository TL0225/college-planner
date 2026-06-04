// CatalogRepository+RequirementScrape.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CatalogRepository+RequirementScrape.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension CatalogRepository {
    func deleteCourseOverride(universityID: UUID, courseCode: String) throws {
        guard let override = try fetchCourseOverride(universityID: universityID, courseCode: courseCode) else {
            return
        }
        context.delete(override)
        ModelMergeCoalescer.scheduleSave(context)
    }

    @discardableResult
    func updateCourseOverrideSyllabus(
        universityID: UUID,
        courseCode: String,
        fileName: String?,
        bookmarkData: Data?,
        fileSizeBytes: Int64?,
        uploadedAt: Date?
    ) throws -> Bool {
        let normalizedCode = courseCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCode.isEmpty else { return false }

        let override: CourseOverride
        if let existing = try fetchCourseOverride(universityID: universityID, courseCode: normalizedCode) {
            override = existing
        } else {
            override = CourseOverride(courseCode: normalizedCode)
            override.university = try fetchUniversity(id: universityID)
            context.insert(override)
        }

        override.syllabusFileName = fileName
        override.syllabusFileBookmarkData = bookmarkData
        override.syllabusFileSizeBytes = fileSizeBytes ?? 0
        override.syllabusUploadedAt = uploadedAt
        override.lastUpdated = .now
        ModelMergeCoalescer.scheduleSave(context)
        return true
    }

    func upsertCourseInstructorContact(
        universityID: UUID,
        courseCode: String,
        professorName: String?,
        email: String?,
        contactMethod: String?,
        officeHours: String?,
        overwriteExisting: Bool
    ) throws -> Bool {
        let normalizedCode = courseCode
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !normalizedCode.isEmpty else { return false }

        func shouldWrite(_ current: String?) -> Bool {
            if overwriteExisting { return true }
            return (current ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        var didChange = false
        let override: CourseOverride
        if let existing = try fetchCourseOverride(universityID: universityID, courseCode: normalizedCode) {
            override = existing
        } else {
            override = CourseOverride(courseCode: normalizedCode)
            override.university = try fetchUniversity(id: universityID)
            context.insert(override)
            didChange = true
        }

        if let name = professorName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty,
           shouldWrite(override.professor) {
            override.professor = name
            didChange = true
        }

        if didChange {
            override.lastUpdated = .now
            ModelMergeCoalescer.scheduleSave(context)
        }
        return didChange
    }

    /// Replaces requirement rows for `(university, programURL, degreeType)` after a scrape.
    func replaceProgramRequirements(
        universityID: UUID,
        programURL: String,
        degreeType: String,
        major: String,
        categories: [DegreeRequirement],
        requirementsHash: String
    ) throws -> Int {
        let canonicalURL = AcademicProgramHelpers.canonicalizeAcalogURL(programURL)
        var existingDescriptor = FetchDescriptor<CatalogDegreeRequirement>(
            predicate: #Predicate { row in
                row.university?.id == universityID
                    && row.programURL == canonicalURL
                    && row.degreeType == degreeType
            }
        )
        existingDescriptor.fetchLimit = 10_000
        let existing = try context.fetch(existingDescriptor)
        for row in existing {
            context.delete(row)
        }

        let university = try fetchUniversity(id: universityID)
        var inserted = 0
        for (index, category) in categories.enumerated() {
            let name = category.category.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            let entity = CatalogDegreeRequirement(
                id: category.id,
                degreeType: degreeType,
                major: major,
                requirementCategory: name,
                sectionOrder: Int16(index),
                creditsRequired: Int16(max(0, category.creditsRequired))
            )
            entity.university = university
            entity.programURL = canonicalURL
            entity.descriptionText = category.description
            entity.requirementsHash = requirementsHash
            entity.lastScrapedAt = .now
            entity.lastUpdated = .now

            if let required = category.requiredCourses, !required.isEmpty {
                entity.requiredCourses = required.joined(separator: ", ")
            }
            if let detailed = category.requiredCoursesDetailed, !detailed.isEmpty {
                entity.requiredCoursesDetailedJSON = AcademicProgramHelpers.encodeDetailedCourseList(detailed)
            }
            if let selectFrom = category.selectFrom, !selectFrom.isEmpty {
                entity.selectFromJSON = AcademicProgramHelpers.encodeJSONCourseList(selectFrom)
                entity.selectCount = Int16(category.selectCount ?? 0)
            }
            if let selectDetailed = category.selectFromDetailed, !selectDetailed.isEmpty {
                entity.selectFromDetailedJSON = AcademicProgramHelpers.encodeDetailedCourseList(selectDetailed)
            }

            context.insert(entity)
            inserted += 1
        }

        ModelMergeCoalescer.scheduleSave(context)
        return inserted
    }

    func touchProgramRequirementsFreshness(
        universityID: UUID,
        programURL: String,
        degreeType: String
    ) throws {
        let canonicalURL = AcademicProgramHelpers.canonicalizeAcalogURL(programURL)
        var descriptor = FetchDescriptor<CatalogDegreeRequirement>(
            predicate: #Predicate { row in
                row.university?.id == universityID
                    && row.programURL == canonicalURL
                    && row.degreeType == degreeType
            }
        )
        descriptor.fetchLimit = 10_000
        let rows = try context.fetch(descriptor)
        let now = Date()
        for row in rows {
            row.lastScrapedAt = now
            row.lastUpdated = now
        }
        if !rows.isEmpty {
            ModelMergeCoalescer.scheduleSave(context)
        }
    }

    func countDistinctCourseCodesInProgramRequirements(
        universityID: UUID,
        programURL: String,
        degreeType: String
    ) throws -> Int {
        let rows = try fetchDegreeRequirements(
            universityID: universityID,
            programURL: programURL,
            degreeType: degreeType
        )
        var codes = Set<String>()
        for row in rows {
            if let raw = row.requiredCourses, !raw.isEmpty {
                raw.split(separator: ",").forEach {
                    let token = AcademicProgramHelpers.normalizeCourseCodeForProgress(String($0))
                    if !token.isEmpty { codes.insert(token) }
                }
            }
            if let detailedJSON = row.requiredCoursesDetailedJSON,
               let detailed = AcademicProgramHelpers.decodeDetailedCourseList(detailedJSON) {
                detailed.forEach {
                    let token = AcademicProgramHelpers.normalizeCourseCodeForProgress($0.code)
                    if !token.isEmpty { codes.insert(token) }
                }
            }
            for token in AcademicProgramHelpers.decodeJSONCourseList(row.selectFromJSON)
                .map(AcademicProgramHelpers.normalizeCourseCodeForProgress)
                .filter({ !$0.isEmpty }) {
                codes.insert(token)
            }
            if let selectDetailedJSON = row.selectFromDetailedJSON,
               let selectDetailed = AcademicProgramHelpers.decodeDetailedCourseList(selectDetailedJSON) {
                selectDetailed.forEach {
                    let token = AcademicProgramHelpers.normalizeCourseCodeForProgress($0.code)
                    if !token.isEmpty { codes.insert(token) }
                }
            }
        }
        return codes.count
    }
}