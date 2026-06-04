// CatalogPDFRequirementExtractor.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogPDFRequirementExtractor.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CatalogPDFRequirementExtractor {
    static func extractRequirements(from programs: [ScrapedProgram]) -> [DegreeRequirement] {
        var out: [DegreeRequirement] = []
        out.reserveCapacity(programs.count)

        for program in programs {
            let major = program.name
            let degreeType = program.degreeType ?? ""
            guard !degreeType.isEmpty else { continue }

            let irNode = RequirementNodeIR.graphFromRequiredCourseCodes([])
            let descriptionText = RequirementNodeIR.encodeForDescription(irNode)

            out.append(
                DegreeRequirement(
                    degreeType: degreeType,
                    major: major,
                    category: "Requirements",
                    creditsRequired: 30,
                    description: descriptionText
                )
            )
        }

        return out
    }
}
