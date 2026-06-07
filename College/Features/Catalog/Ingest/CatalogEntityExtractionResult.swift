// CatalogEntityExtractionResult.swift
// Feature: Catalog
// Purpose: Catalog module — immutable entity rows produced from DocumentIR.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct CatalogEntityExtractionResult: Codable, Sendable, Equatable {
    struct ProgramRow: Codable, Sendable, Equatable, Identifiable {
        let id: UUID
        let name: String
        let type: String
        let url: String
        let department: String?
        let degreeType: String?
        let entityConfidence: CatalogExtractionConfidence
        let ownershipConfidence: CatalogExtractionConfidence
        let provenance: CatalogProvenance
        let stableID: UUID?

        init(
            id: UUID = UUID(),
            name: String,
            type: String,
            url: String,
            department: String? = nil,
            degreeType: String? = nil,
            entityConfidence: CatalogExtractionConfidence,
            ownershipConfidence: CatalogExtractionConfidence,
            provenance: CatalogProvenance,
            stableID: UUID? = nil
        ) {
            self.id = id
            self.name = name
            self.type = type
            self.url = url
            self.department = department
            self.degreeType = degreeType
            self.entityConfidence = entityConfidence
            self.ownershipConfidence = ownershipConfidence
            self.provenance = provenance
            self.stableID = stableID
        }
    }

    struct CourseRow: Codable, Sendable, Equatable, Identifiable {
        let id: UUID
        let courseCode: String
        let title: String
        let credits: Double
        let department: String
        let entityConfidence: CatalogExtractionConfidence
        let ownershipConfidence: CatalogExtractionConfidence
        let provenance: CatalogProvenance
        let stableID: UUID?

        init(
            id: UUID = UUID(),
            courseCode: String,
            title: String,
            credits: Double,
            department: String,
            entityConfidence: CatalogExtractionConfidence,
            ownershipConfidence: CatalogExtractionConfidence,
            provenance: CatalogProvenance,
            stableID: UUID? = nil
        ) {
            self.id = id
            self.courseCode = courseCode
            self.title = title
            self.credits = credits
            self.department = department
            self.entityConfidence = entityConfidence
            self.ownershipConfidence = ownershipConfidence
            self.provenance = provenance
            self.stableID = stableID
        }
    }

    struct RequirementRow: Codable, Sendable, Equatable, Identifiable {
        let id: UUID
        let programURL: String
        let categoryLabel: String
        let entityConfidence: CatalogExtractionConfidence
        let ownershipConfidence: CatalogExtractionConfidence
        let provenance: CatalogProvenance
        let stableID: UUID?

        init(
            id: UUID = UUID(),
            programURL: String,
            categoryLabel: String,
            entityConfidence: CatalogExtractionConfidence,
            ownershipConfidence: CatalogExtractionConfidence,
            provenance: CatalogProvenance,
            stableID: UUID? = nil
        ) {
            self.id = id
            self.programURL = programURL
            self.categoryLabel = categoryLabel
            self.entityConfidence = entityConfidence
            self.ownershipConfidence = ownershipConfidence
            self.provenance = provenance
            self.stableID = stableID
        }
    }

    let schoolID: String
    let catalogVersionID: String
    let layoutProfileID: String
    let ingestRunID: UUID
    let extractedAt: Date
    let programs: [ProgramRow]
    let courses: [CourseRow]
    let requirements: [RequirementRow]

    static func build(
        schoolID: String,
        catalogVersionID: String,
        layoutProfileID: String,
        ingestRunID: UUID,
        extractedAt: Date = Date(),
        programs: [ProgramRow] = [],
        courses: [CourseRow] = [],
        requirements: [RequirementRow] = []
    ) -> CatalogEntityExtractionResult {
        CatalogEntityExtractionResult(
            schoolID: schoolID,
            catalogVersionID: catalogVersionID,
            layoutProfileID: layoutProfileID,
            ingestRunID: ingestRunID,
            extractedAt: extractedAt,
            programs: programs,
            courses: courses,
            requirements: requirements
        )
    }
}
