// CourseLeafRequirementSectionConfig.swift
// Feature: Catalog
// Purpose: School-specific CourseLeaf requirement section naming (IR + requirements parser).
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct CourseLeafRequirementSectionConfig: Sendable {
    let primaryRequirementSectionPatterns: [String]
    let blacklistedSectionElementNames: [String]
    let blacklistedContentPatterns: [String]
    let trackVariantSectionElementNames: [String]

    static let `default` = CourseLeafRequirementSectionConfig(
        primaryRequirementSectionPatterns: [
            "curriculumtext", "requirementstext", "bscurriculumtext", "mscurriculumtext", "bacurriculumtext"
        ],
        blacklistedSectionElementNames: ["sampleplanofstudytext", "coursestext", "overviewtext"],
        blacklistedContentPatterns: [
            "sample plan",
            "four-year roadmap",
            "four year roadmap",
            "sc_plangrid",
            "suggested schedule",
            "typical schedule"
        ],
        trackVariantSectionElementNames: ["text", "honorstext", "honorscurriculumtext"]
    )

    static func forSchoolID(_ schoolID: String) -> CourseLeafRequirementSectionConfig {
        switch schoolID {
        case "fordham_university":
            return CourseLeafRequirementSectionConfig(
                primaryRequirementSectionPatterns: [
                    "requirementstext", "curriculumtext", "bscurriculumtext", "mscurriculumtext", "phdcurriculumtext"
                ],
                blacklistedSectionElementNames: Self.default.blacklistedSectionElementNames,
                blacklistedContentPatterns: Self.default.blacklistedContentPatterns,
                trackVariantSectionElementNames: Self.default.trackVariantSectionElementNames
            )
        case "carnegie_mellon_university":
            return CourseLeafRequirementSectionConfig(
                primaryRequirementSectionPatterns: [
                    "bscurriculumtext", "mscurriculumtext", "curriculumtext", "requirementstext",
                    "csadditionalmajorminortext", "computerscienceminortext"
                ],
                blacklistedSectionElementNames: Self.default.blacklistedSectionElementNames,
                blacklistedContentPatterns: Self.default.blacklistedContentPatterns,
                trackVariantSectionElementNames: Self.default.trackVariantSectionElementNames
            )
        default:
            return .default
        }
    }

    func isPrimaryRequirementSection(elementName: String) -> Bool {
        let lower = elementName.lowercased()
        if blacklistedSectionElementNames.contains(where: { lower.contains($0) }) { return false }
        if primaryRequirementSectionPatterns.contains(where: { lower.contains($0) || lower == $0 }) { return true }
        if lower.hasSuffix("curriculumtext") { return true }
        if lower == "requirementstext" { return true }
        return false
    }

    func isBlacklistedSection(elementName: String, html: String) -> Bool {
        let lowerName = elementName.lowercased()
        if blacklistedSectionElementNames.contains(where: { lowerName.contains($0) }) { return true }
        let lowerHTML = html.lowercased()
        return blacklistedContentPatterns.contains(where: { lowerHTML.contains($0) })
    }

    func matchesDegreeTypeSection(elementName: String, degreeType: String?) -> Bool {
        guard let degreeType else { return true }
        let lower = elementName.lowercased()
        let dt = degreeType.lowercased()
        if lower.contains("bscurriculum") || lower.contains("bacurriculum") {
            return dt.contains("bachelor") || dt.contains(" bs") || dt == "bs" || dt.contains("b.s")
        }
        if lower.contains("mscurriculum") {
            return dt.contains("master") || dt.contains(" ms") || dt == "ms"
        }
        if lower.contains("minor") {
            return dt.contains("minor")
        }
        return true
    }

    func isTrackVariantSection(elementName: String, html: String) -> Bool {
        let lowerName = elementName.lowercased()
        if trackVariantSectionElementNames.contains(where: { lowerName.contains($0) }) {
            let lowerHTML = html.lowercased()
            return lowerHTML.contains("honors program") || lowerHTML.contains("honors track") || lowerHTML.contains("honors curriculum")
        }
        return false
    }

    func trackID(forElementName: String, html: String) -> String {
        if html.lowercased().contains("honors") { return "honors" }
        return "track-\(forElementName.lowercased())"
    }

    func trackDisplayName(forElementName: String, html: String) -> String {
        if html.lowercased().contains("honors program") { return "Honors Program" }
        return forElementName
    }
}
