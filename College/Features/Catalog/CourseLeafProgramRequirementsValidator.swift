// CourseLeafProgramRequirementsValidator.swift
// Feature: Catalog
// Purpose: Catalog module — Result.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Validates requirements extraction quality for a known program URL (not URL discovery).
enum CourseLeafProgramRequirementsValidator {
    enum ReasonCode: String, Sendable {
        case allowedEmpty = "ALLOWED_EMPTY"
        case noCurriculumSection = "NO_CURRICULUM_SECTION"
        case noCategories = "NO_CATEGORIES"
        case parseEmpty = "PARSE_EMPTY"
        case undercountCodes = "UNDERCOUNT_CODES"
        case missingRowCredits = "MISSING_ROW_CREDITS"
        case breakdownEmpty = "BREAKDOWN_EMPTY"
        case blacklistCategory = "BLACKLIST_CATEGORY"
        case fetchIndexXMLFailed = "FETCH_INDEX_XML_FAILED"
    }

    struct Result: Sendable {
        let programURL: String
        let passed: Bool
        let reason: ReasonCode?
        let categoriesCount: Int
        let codesParsed: Int
        let expectedCodeCount: Int
        let visibleBreakdownCategories: Int
    }

    struct SchoolWideReport: Sendable {
        let schoolID: String
        let inputProgramURLs: Int
        let allowedEmpty: Int
        let validated: Int
        let passed: Int
        let failures: [Result]
        var passRate: Double {
            guard validated > 0 else { return 0 }
            return Double(passed) / Double(validated)
        }
    }

    static func validate(
        programURL: String,
        schoolID: String,
        degreeType: String? = nil,
        xml: String? = nil
    ) async -> Result {
        let trimmed = programURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pageURL = URL(string: trimmed) else {
            return Result(programURL: trimmed, passed: false, reason: .fetchIndexXMLFailed, categoriesCount: 0, codesParsed: 0, expectedCodeCount: 0, visibleBreakdownCategories: 0)
        }

        let xmlPayload: String
        do {
            if let xml {
                xmlPayload = xml
            } else {
                xmlPayload = try await CourseLeafXMLClient.fetchIndexXML(forProgramURL: trimmed)
            }
        } catch {
            return Result(programURL: trimmed, passed: false, reason: .fetchIndexXMLFailed, categoriesCount: 0, codesParsed: 0, expectedCodeCount: 0, visibleBreakdownCategories: 0)
        }

        let fragments = CourseLeafRequirementsParser.extractRequirementFragments(
            from: xmlPayload,
            schoolID: schoolID,
            programURL: pageURL,
            degreeType: degreeType
        )

        if fragments.baselineHTML.isEmpty {
            return Result(programURL: trimmed, passed: true, reason: .allowedEmpty, categoriesCount: 0, codesParsed: 0, expectedCodeCount: 0, visibleBreakdownCategories: 0)
        }

        if !fragments.baselineHTML.lowercased().contains("sc_courselist") {
            return Result(programURL: trimmed, passed: true, reason: .allowedEmpty, categoriesCount: 0, codesParsed: 0, expectedCodeCount: 0, visibleBreakdownCategories: 0)
        }

        let requirements: [DegreeRequirement]
        do {
            requirements = try CourseLeafRequirementsParser.parseRequirements(
                fromXML: xmlPayload,
                programURL: pageURL,
                schoolID: schoolID,
                degreeType: degreeType
            )
        } catch {
            return Result(programURL: trimmed, passed: false, reason: .parseEmpty, categoriesCount: 0, codesParsed: 0, expectedCodeCount: expectedCodes(in: fragments.baselineHTML), visibleBreakdownCategories: 0)
        }

        if requirements.isEmpty {
            return Result(programURL: trimmed, passed: false, reason: .parseEmpty, categoriesCount: 0, codesParsed: 0, expectedCodeCount: expectedCodes(in: fragments.baselineHTML), visibleBreakdownCategories: 0)
        }

        let categories = Set(requirements.map(\.category).filter { $0 != "__PROGRAM_TOTAL_CREDITS__" })
        if categories.isEmpty {
            return Result(programURL: trimmed, passed: false, reason: .noCategories, categoriesCount: 0, codesParsed: 0, expectedCodeCount: expectedCodes(in: fragments.baselineHTML), visibleBreakdownCategories: 0)
        }

        for cat in categories {
            let lower = cat.lowercased()
            if lower.contains("sample plan") || lower.contains("roadmap") || lower.contains("sc_plangrid") {
                return Result(programURL: trimmed, passed: false, reason: .blacklistCategory, categoriesCount: categories.count, codesParsed: parsedCodeCount(requirements), expectedCodeCount: expectedCodes(in: fragments.baselineHTML), visibleBreakdownCategories: 0)
            }
        }

        let expected = expectedCodes(in: fragments.baselineHTML)
        let parsed = parsedCodeCount(requirements)
        if expected > 0 {
            let ratio = Double(parsed) / Double(expected)
            if ratio < 0.85 {
                return Result(programURL: trimmed, passed: false, reason: .undercountCodes, categoriesCount: categories.count, codesParsed: parsed, expectedCodeCount: expected, visibleBreakdownCategories: 0)
            }
        }

        let visible = RequirementBreakdownBuilder.visibleCategories(from: requirements)
        if visible.isEmpty {
            return Result(programURL: trimmed, passed: false, reason: .breakdownEmpty, categoriesCount: categories.count, codesParsed: parsed, expectedCodeCount: expected, visibleBreakdownCategories: 0)
        }

        return Result(
            programURL: trimmed,
            passed: true,
            reason: nil,
            categoriesCount: categories.count,
            codesParsed: parsed,
            expectedCodeCount: expected,
            visibleBreakdownCategories: visible.count
        )
    }

    static func validateSchoolWide(
        programs: [ScrapedProgram],
        schoolID: String,
        minimumPassRate: Double = 0.99
    ) async -> SchoolWideReport {
        var allowedEmpty = 0
        var passed = 0
        var failures: [Result] = []
        var validated = 0

        for program in programs {
            let result = await validate(
                programURL: program.url,
                schoolID: schoolID,
                degreeType: program.degreeType
            )
            if result.reason == .allowedEmpty {
                allowedEmpty += 1
                continue
            }
            validated += 1
            if result.passed {
                passed += 1
            } else {
                failures.append(result)
            }
        }

        return SchoolWideReport(
            schoolID: schoolID,
            inputProgramURLs: programs.count,
            allowedEmpty: allowedEmpty,
            validated: validated,
            passed: passed,
            failures: failures
        )
    }

    private static func expectedCodes(in html: String) -> Int {
        let primaryTableHTML = primaryCourselistTableHTML(from: html)
        return countDistinctCourseCodes(in: primaryTableHTML)
    }

    /// Count bubbles only in the first `sc_courselist` block (baseline requirements), not reference/elective list tables.
    private static func primaryCourselistTableHTML(from html: String) -> String {
        let marker = "<table class=\"sc_courselist\""
        guard let start = html.range(of: marker, options: .caseInsensitive) else { return html }
        let tail = html[start.lowerBound...]
        guard let end = tail.range(of: "</table>", options: .caseInsensitive) else { return String(tail) }
        return String(tail[..<end.upperBound])
    }

    private static func countDistinctCourseCodes(in html: String) -> Int {
        let bubblePattern = try? NSRegularExpression(pattern: "data-code-bubble=\"([^\"]+)\"", options: .caseInsensitive)
        let showCoursePattern = try? NSRegularExpression(pattern: "showCourse\\([^,]+,\\s*['\"]([^'\"]+)['\"]", options: .caseInsensitive)
        let codeCellPattern = try? NSRegularExpression(pattern: "<td class=\"codecol\">\\s*([A-Z]{2,}[A-Z0-9/&\\s\\-]{2,})\\s*</td>", options: .caseInsensitive)
        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        var codes = Set<String>()
        for pattern in [bubblePattern, showCoursePattern, codeCellPattern].compactMap({ $0 }) {
            for match in pattern.matches(in: html, options: [], range: nsRange) {
                guard match.numberOfRanges >= 2, let r = Range(match.range(at: 1), in: html) else { continue }
                let code = String(html[r]).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if !code.isEmpty { codes.insert(code) }
            }
        }
        return codes.count
    }

    private static func parsedCodeCount(_ requirements: [DegreeRequirement]) -> Int {
        var codes = Set<String>()
        for req in requirements {
            for c in req.requiredCourses ?? [] { codes.insert(c.uppercased()) }
            for c in req.selectFrom ?? [] { codes.insert(c.uppercased()) }
        }
        return codes.count
    }
}
