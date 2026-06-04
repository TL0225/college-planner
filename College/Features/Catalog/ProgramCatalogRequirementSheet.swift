// ProgramCatalogRequirementSheet.swift
// Feature: Catalog
// Purpose: Catalog module — ProgramCatalogRequirementSheet.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Parsed Modern Campus program requirements page (stored as JSON on `DegreeRequirementEntity`).
struct ProgramCatalogRequirementSheet: Codable, Sendable {
    struct RequirementGroup: Codable, Sendable {
        var groupName: String
        var courseOptions: [String]
        var chooseCount: Int?

        init(groupName: String = "", courseOptions: [String] = [], chooseCount: Int? = nil) {
            self.groupName = groupName
            self.courseOptions = courseOptions
            self.chooseCount = chooseCount
        }
    }

    var programName: String
    var totalCreditsRequired: Int?
    var requirementGroups: [RequirementGroup]
    var courseCoidMap: [String: String]

    init(
        programName: String = "",
        totalCreditsRequired: Int? = nil,
        requirementGroups: [RequirementGroup] = [],
        courseCoidMap: [String: String] = [:]
    ) {
        self.programName = programName
        self.totalCreditsRequired = totalCreditsRequired
        self.requirementGroups = requirementGroups
        self.courseCoidMap = courseCoidMap
    }

    /// Expand sheet groups into canonical `DegreeRequirement` rows (Modern Campus hydration contract).
    func expandedDegreeRequirements() -> [DegreeRequirement] {
        let major = programName.trimmingCharacters(in: .whitespacesAndNewlines)
        var results: [DegreeRequirement] = []
        results.reserveCapacity(requirementGroups.count + 1)

        for group in requirementGroups {
            let title = group.groupName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            let optionDetails = group.courseOptions
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { CourseDetail(code: $0, title: nil, credits: nil) }
            let chooseCount = group.chooseCount ?? 0

            if !optionDetails.isEmpty, chooseCount > 0 {
                results.append(
                    RequirementRowNormalizer.makeRequirement(
                        major: major.isEmpty ? "Unknown" : major,
                        parentCategory: title,
                        displayTitle: chooseCount < optionDetails.count ? "Select from following" : title,
                        kind: .chooseOne,
                        selectFrom: optionDetails,
                        description: title,
                        selectCount: chooseCount
                    )
                )
            } else if !optionDetails.isEmpty {
                results.append(
                    RequirementRowNormalizer.makeRequirement(
                        major: major.isEmpty ? "Unknown" : major,
                        parentCategory: title,
                        displayTitle: title,
                        kind: .courseList,
                        required: optionDetails,
                        description: title
                    )
                )
            } else if chooseCount > 0 {
                results.append(
                    RequirementRowNormalizer.makeRequirement(
                        major: major.isEmpty ? "Unknown" : major,
                        parentCategory: title,
                        displayTitle: title,
                        kind: .ruleBucket,
                        description: title,
                        selectCount: chooseCount
                    )
                )
            } else {
                results.append(
                    RequirementRowNormalizer.makeRequirement(
                        major: major.isEmpty ? "Unknown" : major,
                        parentCategory: title,
                        displayTitle: title,
                        kind: .prose,
                        description: title
                    )
                )
            }
        }

        if let total = totalCreditsRequired, total > 0 {
            results.append(
                DegreeRequirement(
                    degreeType: "Program Sheet",
                    major: major.isEmpty ? "Unknown" : major,
                    category: "__PROGRAM_TOTAL_CREDITS__",
                    creditsRequired: total,
                    description: "Program catalog sheet total."
                )
            )
        }

        return results
    }
}
