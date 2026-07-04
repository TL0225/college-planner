// ResumeHeadingParser.swift
// Feature: Career / ResumeParsing

import Foundation

enum ResumeHeadingParser {
    static func parseExperienceHeading(_ line: String) -> (title: String, company: String, location: String?) {
        let separators = [" – ", " - ", " | ", " — "]
        for sep in separators where line.contains(sep) {
            let parts = line.components(separatedBy: sep).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if parts.count >= 2 {
                let location = parts.count >= 3 ? parts[2] : nil
                return (parts[0], parts[1], location)
            }
        }
        return (line, "", nil)
    }

    static func inferEmploymentType(title: String, sectionHeader: String?) -> ParsedEmploymentType? {
        let blob = ([sectionHeader, title].compactMap { $0?.lowercased() }).joined(separator: " ")
        if blob.contains("intern") { return .internship }
        if blob.contains("extern") { return .externship }
        if blob.contains("co-op") || blob.contains("coop") { return .coOp }
        if blob.contains("contract") || blob.contains("consult") { return .contract }
        if blob.contains("volunteer") { return .volunteer }
        if blob.contains("part-time") || blob.contains("part time") { return .partTime }
        return .fullTime
    }
}
