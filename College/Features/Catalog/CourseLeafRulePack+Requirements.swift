// CourseLeafRulePack+Requirements.swift
// Feature: Catalog
// Purpose: Catalog module — CourseLeafRulePack+Requirements.
// Data: CollegePersistence / repositories when applicable.

import Foundation

extension CourseLeafRulePack {
    var primaryRequirementSectionPatterns: [String] {
        switch schoolID {
        case "fordham_university":
            return ["requirementstext", "curriculumtext", "bscurriculumtext", "mscurriculumtext", "phdcurriculumtext"]
        case "carnegie_mellon_university":
            return ["bscurriculumtext", "mscurriculumtext", "curriculumtext", "requirementstext", "csadditionalmajorminortext", "computerscienceminortext"]
        default:
            return ["curriculumtext", "requirementstext", "bscurriculumtext", "mscurriculumtext", "bacurriculumtext"]
        }
    }

    var blacklistedSectionElementNames: [String] {
        ["sampleplanofstudytext", "coursestext", "overviewtext"]
    }

    var blacklistedContentPatterns: [String] {
        [
            "sample plan",
            "four-year roadmap",
            "four year roadmap",
            "sc_plangrid",
            "suggested schedule",
            "typical schedule"
        ]
    }

    var trackVariantSectionElementNames: [String] {
        ["text", "honorstext", "honorscurriculumtext"]
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
