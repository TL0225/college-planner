// CatalogSchoolImportWriter.swift
// Feature: Core/Data
// Purpose: Off-main SwiftData writes for catalog school import.

import Foundation
import SwiftData

enum CatalogSchoolImportWriter {
    struct PreparedImport: Sendable {
        let universityID: UUID
        let universityName: String
        let courseChunks: [[CatalogRepository.CourseImportInput]]
        let requirementInputs: [CatalogRepository.DegreeRequirementImportInput]
        let scrapedCodes: Set<String>
        let archiveMissingCourses: Bool
    }

    static func chunk(
        _ inputs: [CatalogRepository.CourseImportInput],
        size: Int = 500
    ) -> [[CatalogRepository.CourseImportInput]] {
        guard !inputs.isEmpty else { return [] }
        var chunks: [[CatalogRepository.CourseImportInput]] = []
        chunks.reserveCapacity((inputs.count / size) + 1)
        var index = 0
        while index < inputs.count {
            let end = min(index + size, inputs.count)
            chunks.append(Array(inputs[index..<end]))
            index = end
        }
        return chunks
    }

    static func upsertCourses(
        universityID: UUID,
        inputs: [CatalogRepository.CourseImportInput],
        context: ModelContext
    ) throws {
        guard !inputs.isEmpty else { return }
        guard try fetchUniversity(id: universityID, context: context) != nil else { return }

        for input in inputs {
            let code = input.courseCode.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty else { continue }

            var descriptor = FetchDescriptor<CourseCatalog>(
                predicate: #Predicate { course in
                    course.university?.id == universityID && course.courseCode == code
                }
            )
            descriptor.fetchLimit = 1

            let course: CourseCatalog
            if let existing = try context.fetch(descriptor).first {
                course = existing
            } else {
                course = CourseCatalog(courseCode: code, title: input.title, credits: input.credits)
                course.university = try fetchUniversity(id: universityID, context: context)
                context.insert(course)
            }

            course.title = input.title.isEmpty ? code : input.title
            course.credits = input.credits
            course.descriptionText = input.descriptionText
            course.department = input.department
            course.isArchived = input.isArchived
            course.lastUpdated = .now
            if let stableID = input.catalogStableID {
                course.catalogStableID = stableID
            }
            if let provenanceJSON = input.provenanceJSON {
                course.provenanceJSON = provenanceJSON
            }
            if let prerequisiteRulesJSON = input.prerequisiteRulesJSON {
                course.prerequisiteRulesJSON = prerequisiteRulesJSON
            }
            if let extractionConfidence = input.extractionConfidence {
                course.extractionConfidence = extractionConfidence
            }
            if let signalSource = input.signalSource {
                course.signalSource = signalSource
            }
            if let parserVersion = input.parserVersion {
                course.parserVersion = parserVersion
            }
            if let departmentLinkConfidence = input.departmentLinkConfidence {
                course.departmentLinkConfidence = departmentLinkConfidence
            }
            if let departmentID = input.departmentID,
               let department = try fetchDepartment(id: departmentID, context: context) {
                course.departmentEntity = department
            }
        }
    }

    static func upsertDegreeRequirements(
        universityID: UUID,
        inputs: [CatalogRepository.DegreeRequirementImportInput],
        context: ModelContext
    ) throws {
        guard !inputs.isEmpty else { return }
        guard try fetchUniversity(id: universityID, context: context) != nil else { return }

        var existingDescriptor = FetchDescriptor<CatalogDegreeRequirement>(
            predicate: #Predicate { $0.university?.id == universityID }
        )
        existingDescriptor.fetchLimit = 20_000
        let existing = try context.fetch(existingDescriptor)
        var byKey: [String: CatalogDegreeRequirement] = [:]
        for row in existing {
            let key = "\(row.major.lowercased())||\(row.requirementCategory.lowercased())"
            byKey[key] = row
        }

        for input in inputs {
            let major = input.major.trimmingCharacters(in: .whitespacesAndNewlines)
            let category = input.category.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !major.isEmpty, !category.isEmpty else { continue }

            let key = "\(major.lowercased())||\(category.lowercased())"
            let entity: CatalogDegreeRequirement
            if let existingEntity = byKey[key] {
                entity = existingEntity
            } else {
                entity = CatalogDegreeRequirement(
                    id: input.id,
                    degreeType: input.degreeType,
                    major: major,
                    requirementCategory: category,
                    sectionOrder: input.sectionOrder,
                    creditsRequired: input.creditsRequired
                )
                entity.university = try fetchUniversity(id: universityID, context: context)
                context.insert(entity)
                byKey[key] = entity
            }

            entity.degreeType = input.degreeType
            entity.major = major
            entity.requirementCategory = category
            entity.sectionOrder = input.sectionOrder
            entity.creditsRequired = input.creditsRequired
            entity.descriptionText = input.descriptionText
            if let programURL = input.programURL?.trimmingCharacters(in: .whitespacesAndNewlines), !programURL.isEmpty {
                entity.programURL = AcademicProgramHelpers.canonicalizeAcalogURL(programURL)
            }
            entity.requiredCourses = input.requiredCourses
            entity.requiredCoursesDetailedJSON = input.requiredCoursesDetailedJSON
            entity.selectFromJSON = input.selectFromJSON
            entity.selectFromDetailedJSON = input.selectFromDetailedJSON
            entity.selectCount = input.selectCount
            entity.requirementKind = input.requirementKind
            entity.parentCategory = input.parentCategory
            entity.displayTitle = input.displayTitle
            entity.trackVariant = input.trackVariant
            entity.requirementsHash = input.requirementsHash
            entity.lastScrapedAt = .now
            entity.lastUpdated = .now
            if let stableID = input.catalogStableID {
                entity.catalogStableID = stableID
            }
            if let provenanceJSON = input.provenanceJSON {
                entity.provenanceJSON = provenanceJSON
            }
            if let extractionConfidence = input.extractionConfidence {
                entity.extractionConfidence = extractionConfidence
            }
            if let signalSource = input.signalSource {
                entity.signalSource = signalSource
            }
            if let parserVersion = input.parserVersion {
                entity.parserVersion = parserVersion
            }
            if let programAttachmentConfidence = input.programAttachmentConfidence {
                entity.programAttachmentConfidence = programAttachmentConfidence
            }
            if let requirementPredicateJSON = input.requirementPredicateJSON {
                entity.requirementPredicateJSON = requirementPredicateJSON
            }
            if let catalogEditionID = input.catalogEditionID {
                entity.catalogEditionID = catalogEditionID
            }
        }
    }

    static func archiveCoursesNotInCodes(
        universityID: UUID,
        scrapedCodes: Set<String>,
        context: ModelContext
    ) throws {
        var descriptor = FetchDescriptor<CourseCatalog>(
            predicate: #Predicate { $0.university?.id == universityID }
        )
        descriptor.fetchLimit = 50_000
        let existing = try context.fetch(descriptor)
        for course in existing {
            let key = CatalogImportTransforms.normalizeCourseCode(course.courseCode)
            guard !scrapedCodes.contains(key) else { continue }
            course.isArchived = true
            course.lastUpdated = .now
        }
    }

    static func activateUniversity(id: UUID, name: String, context: ModelContext) throws {
        let all = try context.fetch(FetchDescriptor<University>())
        for university in all {
            university.isActive = university.id == id
            if university.id == id {
                university.name = name
            }
        }
        if try fetchUniversity(id: id, context: context) == nil {
            let university = University(id: id, name: name, isActive: true)
            context.insert(university)
        }
    }

    static func persistPreparedImport(_ prepared: PreparedImport, context: ModelContext) throws {
        for chunk in prepared.courseChunks {
            try upsertCourses(universityID: prepared.universityID, inputs: chunk, context: context)
        }
        if !prepared.requirementInputs.isEmpty {
            try upsertDegreeRequirements(
                universityID: prepared.universityID,
                inputs: prepared.requirementInputs,
                context: context
            )
        }
        if prepared.archiveMissingCourses {
            try archiveCoursesNotInCodes(
                universityID: prepared.universityID,
                scrapedCodes: prepared.scrapedCodes,
                context: context
            )
        }
        try activateUniversity(id: prepared.universityID, name: prepared.universityName, context: context)
        if context.hasChanges {
            try context.save()
        }
    }

    private static func fetchUniversity(id: UUID, context: ModelContext) throws -> University? {
        var descriptor = FetchDescriptor<University>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private static func fetchDepartment(id: UUID, context: ModelContext) throws -> Department? {
        var descriptor = FetchDescriptor<Department>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
