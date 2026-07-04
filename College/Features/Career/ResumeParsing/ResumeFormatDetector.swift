// ResumeFormatDetector.swift
// Feature: Career / ResumeParsing

import Foundation

enum ResumeFormatDetector {
    static func detect(plainText: String, sections: [String]) -> ResumeFormatKind {
        let lower = plainText.lowercased()
        if sections.contains(where: { ResumeSectionAliasRegistry.normalizeHeader($0).contains("education") })
            && lower.contains("expected graduation") {
            return .student
        }
        if lower.contains("publications") || lower.contains("peer-reviewed") {
            return .academicCV
        }
        if sections.filter({ ResumeSectionAliasRegistry.category(forHeader: $0) == .experience }).count == 0
            && lower.contains("skills") {
            return .functional
        }
        if sections.count >= 4 { return .hybrid }
        return .chronological
    }
}
