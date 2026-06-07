// CatalogRepository+Import.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CourseImportInput.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension CatalogRepository {
    struct CourseImportInput: Sendable {
        let courseCode: String
        let title: String
        let credits: Int16
        let descriptionText: String?
        let department: String?
        let departmentID: UUID?
        let isArchived: Bool
        let catalogStableID: UUID?
        let provenanceJSON: String?
        let prerequisiteRulesJSON: String?
    }

    struct DegreeRequirementImportInput: Sendable {
        let id: UUID
        let major: String
        let category: String
        let degreeType: String
        let programURL: String?
        let sectionOrder: Int16
        let creditsRequired: Int16
        let descriptionText: String?
        let requiredCourses: String?
        let requiredCoursesDetailedJSON: String?
        let selectFromJSON: String?
        let selectFromDetailedJSON: String?
        let selectCount: Int16
        let requirementKind: String?
        let parentCategory: String?
        let displayTitle: String?
        let trackVariant: String?
        let requirementsHash: String?
        let catalogStableID: UUID?
        let provenanceJSON: String?
    }

    @discardableResult
    func ensureUniversityForImport(
        id: UUID,
        name: String,
        catalogURL: String?,
        catalogFormat: String = "github"
    ) throws -> University {
        let university = try ensureUniversity(id: id, name: name, isActive: false)
        if let catalogURL, !catalogURL.isEmpty {
            university.catalogURL = catalogURL
        }
        university.lastCatalogSync = .now
        university.catalogFormat = catalogFormat
        return university
    }

    func activateUniversity(id: UUID, name: String) throws {
        let all = try context.fetch(FetchDescriptor<University>())
        for university in all {
            university.isActive = university.id == id
            if university.id == id {
                university.name = name
            }
        }
        _ = try ensureUniversity(id: id, name: name, isActive: true)
        ModelMergeCoalescer.scheduleSave(context)
    }

    func departmentLookup(universityID: UUID) throws -> [String: Department] {
        var descriptor = FetchDescriptor<Department>(
            predicate: #Predicate { $0.university?.id == universityID }
        )
        descriptor.fetchLimit = 10_000
        let departments = try context.fetch(descriptor)
        var lookup: [String: Department] = [:]
        for department in departments {
            let nameKey = CatalogImportTransforms.normalize(department.name).lowercased()
            if !nameKey.isEmpty { lookup[nameKey] = department }
            if let code = department.code {
                let codeKey = CatalogImportTransforms.normalize(code).lowercased()
                if !codeKey.isEmpty { lookup[codeKey] = department }
            }
        }
        return lookup
    }

    func upsertImportedCourses(universityID: UUID, inputs: [CourseImportInput]) throws {
        guard !inputs.isEmpty else { return }
        guard try fetchUniversity(id: universityID) != nil else { return }

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
                course.university = try fetchUniversity(id: universityID)
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
            if let departmentID = input.departmentID,
               let department = try? fetchDepartment(id: departmentID) {
                course.departmentEntity = department
            }
        }

        ModelMergeCoalescer.scheduleSave(context)
    }

    func upsertDegreeRequirements(
        universityID: UUID,
        inputs: [DegreeRequirementImportInput]
    ) throws {
        guard try fetchUniversity(id: universityID) != nil else { return }

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
                entity.university = try fetchUniversity(id: universityID)
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
        }

        ModelMergeCoalescer.scheduleSave(context)
    }

    func archiveCoursesNotInCodes(universityID: UUID, scrapedCodes: Set<String>) throws {
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
        ModelMergeCoalescer.scheduleSave(context)
    }

    private func fetchDepartment(id: UUID) throws -> Department? {
        var descriptor = FetchDescriptor<Department>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}