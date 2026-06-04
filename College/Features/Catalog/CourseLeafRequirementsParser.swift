// CourseLeafRequirementsParser.swift
// Feature: Catalog
// Purpose: Catalog module — RequirementFragments.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftSoup

/// Fetches program `index.xml` and parses degree requirements from curriculum CDATA.
enum CourseLeafRequirementsParser {
    struct RequirementFragments: Sendable {
        let baselineHTML: String
        let trackVariants: [(trackID: String, displayName: String, html: String)]
    }

    struct ParseDiagnostics: Sendable, Equatable {
        let signature: String
        let usedBaselineSection: Bool
        let categoriesFound: Int
        let requiredCourseCount: Int
        let selectCourseCount: Int
    }

    /// Parse requirements from already-fetched program `index.xml`.
    static func parseRequirements(
        fromXML xml: String,
        programURL: URL,
        schoolID: String,
        degreeType: String? = nil,
        programName: String? = nil
    ) throws -> [DegreeRequirement] {
        let fragments = extractRequirementFragments(from: xml, schoolID: schoolID, programURL: programURL, degreeType: degreeType)
        guard !fragments.baselineHTML.isEmpty else { return [] }
        let wrapped = wrapHTMLFragment(fragments.baselineHTML)
        let doc = try SwiftSoup.parse(wrapped, programURL.absoluteString)
        let parsed = try CourseLeafCourselistHTMLParser.parse(doc: doc, logger: DebugLogger.shared) ?? []
        return stampProgramMetadata(
            parsed,
            programName: programName,
            degreeType: degreeType,
            programURL: programURL
        )
    }

    /// Attach real program name/degree type (parser rows default to `Unknown`).
    static func stampProgramMetadata(
        _ requirements: [DegreeRequirement],
        programName: String?,
        degreeType: String?,
        programURL: URL
    ) -> [DegreeRequirement] {
        let title = (programName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let majorLabel = title.isEmpty ? programURL.lastPathComponent.replacingOccurrences(of: "-", with: " ").capitalized : title
        let dt = (degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let degreeLabel = dt.isEmpty ? "Unknown" : dt
        return requirements.map { $0.stamping(major: majorLabel, degreeType: degreeLabel) }
    }

    /// Fetch `index.xml` for a program page and parse requirements.
    static func scrapeRequirements(programURL: String, schoolID: String, degreeType: String? = nil) async throws -> [DegreeRequirement] {
        let trimmed = programURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pageURL = URL(string: trimmed) else { throw ScraperError.invalidURL }
        let xml = try await CourseLeafXMLClient.fetchIndexXML(forProgramURL: trimmed)
        let programName = programTitle(fromXML: xml, fallbackURL: pageURL)
        return try parseRequirements(
            fromXML: xml,
            programURL: pageURL,
            schoolID: schoolID,
            degreeType: degreeType ?? CourseLeafProgramURLParser.degreeTypeFromTitle(programName),
            programName: programName
        )
    }

    static func programTitle(fromXML xml: String, fallbackURL: URL) -> String {
        let titlePattern = try? NSRegularExpression(pattern: "<title>(.*?)</title>", options: [.caseInsensitive, .dotMatchesLineSeparators])
        let nsRange = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        if let titleMatch = titlePattern?.firstMatch(in: xml, options: [], range: nsRange),
           let range = Range(titleMatch.range(at: 1), in: xml) {
            let title = String(xml[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { return title }
        }
        return fallbackURL.lastPathComponent.replacingOccurrences(of: "-", with: " ").capitalized
    }

    static func scrapeRequirementsWithDiagnostics(
        programURL: String,
        schoolID: String,
        degreeType: String? = nil
    ) async throws -> (requirements: [DegreeRequirement], diagnostics: ParseDiagnostics) {
        let requirements = try await scrapeRequirements(programURL: programURL, schoolID: schoolID, degreeType: degreeType)
        let requiredCount = requirements.reduce(0) { $0 + ($1.requiredCourses?.count ?? 0) }
        let selectCount = requirements.reduce(0) { $0 + ($1.selectFrom?.count ?? 0) }
        let categories = Set(requirements.map(\.category).filter { $0 != "__PROGRAM_TOTAL_CREDITS__" })
        let diagnostics = ParseDiagnostics(
            signature: "courseleaf-index-xml",
            usedBaselineSection: !requirements.isEmpty,
            categoriesFound: categories.count,
            requiredCourseCount: requiredCount,
            selectCourseCount: selectCount
        )
        return (requirements, diagnostics)
    }

    static func extractRequirementFragments(
        from xml: String,
        schoolID: String,
        programURL: URL,
        degreeType: String? = nil
    ) -> RequirementFragments {
        let rules = CourseLeafRulePack.forSchoolID(schoolID)
        let sections = parseNamedSections(from: xml)

        var baselineParts: [String] = []
        for section in sections {
            guard rules.isPrimaryRequirementSection(elementName: section.elementName) else { continue }
            if rules.isBlacklistedSection(elementName: section.elementName, html: section.html) { continue }
            if !rules.matchesDegreeTypeSection(elementName: section.elementName, degreeType: degreeType) { continue }
            baselineParts.append(section.html)
        }

        var trackVariants: [(String, String, String)] = []
        for section in sections {
            guard rules.isTrackVariantSection(elementName: section.elementName, html: section.html) else { continue }
            let trackID = rules.trackID(forElementName: section.elementName, html: section.html)
            let displayName = rules.trackDisplayName(forElementName: section.elementName, html: section.html)
            trackVariants.append((trackID, displayName, section.html))
        }

        return RequirementFragments(
            baselineHTML: baselineParts.joined(separator: "\n"),
            trackVariants: trackVariants
        )
    }

    struct NamedSection {
        let elementName: String
        let html: String
    }

    static func parseNamedSections(from xml: String) -> [NamedSection] {
        guard xml.contains("<courseleaf") else { return [] }
        var results: [NamedSection] = []
        let pattern = try? NSRegularExpression(
            pattern: "<([a-zA-Z0-9_]+)(?:\\s+[^>]*)?>\\s*<!\\[CDATA\\[(.*?)\\]\\]>\\s*</\\1>",
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        )
        let nsRange = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        guard let pattern else { return [] }
        for match in pattern.matches(in: xml, options: [], range: nsRange) {
            guard match.numberOfRanges >= 3,
                  let nameRange = Range(match.range(at: 1), in: xml),
                  let cdataRange = Range(match.range(at: 2), in: xml) else { continue }
            let name = String(xml[nameRange]).lowercased()
            let html = String(xml[cdataRange])
            guard !html.isEmpty else { continue }
            results.append(NamedSection(elementName: name, html: html))
        }
        return results
    }

    static func wrapHTMLFragment(_ fragment: String) -> String {
        """
        <html><body>
        \(fragment)
        </body></html>
        """
    }

    /// Test helper: parse requirements from fixture XML on disk.
    static func parseRequirementsFromFixtureXML(
        _ xml: String,
        programURL: String,
        schoolID: String,
        programName: String? = nil
    ) throws -> [DegreeRequirement] {
        guard let url = URL(string: programURL) else { throw ScraperError.invalidURL }
        return try parseRequirements(
            fromXML: xml,
            programURL: url,
            schoolID: schoolID,
            programName: programName ?? url.deletingLastPathComponent().lastPathComponent
        )
    }
}
