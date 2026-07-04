// CoursedogRequirementsParser.swift
// Feature: Catalog
// Purpose: Requirements scrape for Coursedog SPA program detail pages.

import Foundation
import SwiftSoup

enum CoursedogRequirementsParser {
    @MainActor
    static func scrapeRequirementsWithDiagnostics(
        programURL: String
    ) async throws -> (requirements: [DegreeRequirement], diagnostics: UniversalCatalogScraper.ProgramRequirementsDiagnostics) {
        let trimmed = programURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ScraperError.invalidURL }

        let html = try await CoursedogEngine.fetchProgramDetailHTML(programURL: trimmed)
        let parsed = try UniversalCatalogScraper.invoke_parseProgramRequirementsHTML_forTests(html, baseURL: trimmed)
        if !parsed.requirements.isEmpty {
            return parsed
        }

        let fallback = parseCourseCodesFromRenderedText(html)
        guard !fallback.isEmpty else { return parsed }

        let requirement = DegreeRequirement(
            degreeType: "Program",
            major: "Program",
            category: "Program Courses",
            requiredCourses: fallback.sorted(),
            creditsRequired: 0
        )
        let diagnostics = UniversalCatalogScraper.ProgramRequirementsDiagnostics(
            signature: "coursedog-text-fallback",
            usedMajorRequirementsSection: true,
            categoriesFound: 1,
            requiredCourseCount: fallback.count,
            selectCourseCount: 0,
            uniqueCourseCount: fallback.count
        )
        return ([requirement], diagnostics)
    }

    /// Rutgers-style catalogs expose `14:440` codes in rendered body text after SPA tabs load.
    static func parseCourseCodesFromRenderedText(_ html: String) -> [String] {
        let text: String = {
            if let doc = try? SwiftSoup.parse(html) {
                return (try? doc.text()) ?? html
            }
            return html
        }()
        guard !text.isEmpty else { return [] }

        var codes = Set<String>()
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)

        if let rutgersPattern = try? NSRegularExpression(pattern: #"\b(\d{2}:\d{3})\b"#) {
            for match in rutgersPattern.matches(in: text, options: [], range: nsRange) {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                codes.insert(String(text[range]))
            }
        }

        if let subjectPattern = try? NSRegularExpression(pattern: #"\b([A-Z]{2,6})\s+(\d{2,4}[A-Z]?)\b"#) {
            for match in subjectPattern.matches(in: text, options: [], range: nsRange) {
                guard match.numberOfRanges >= 3,
                      let subjectRange = Range(match.range(at: 1), in: text),
                      let numberRange = Range(match.range(at: 2), in: text) else { continue }
                codes.insert("\(text[subjectRange]) \(text[numberRange])")
            }
        }

        return Array(codes)
    }
}
