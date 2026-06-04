// CourseLeafEngine.swift
// Feature: Catalog
// Purpose: Catalog module — CrawlOutput.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import CryptoKit
import SwiftSoup

enum CourseLeafEngine {
    struct CrawlOutput: Sendable {
        let courses: [CatalogCourse]
        let programs: [ScrapedProgram]
        let sourceSignature: String
    }

    struct PageParseResult: Sendable {
        let courses: [CatalogCourse]
        let programs: [ScrapedProgram]
    }

    private static var session: URLSession { CourseLeafXMLClient.session }

    /// Parses a single CourseLeaf `index.xml` page. Used by golden fixture tests.
    static func parseCatalogPage(xml: String, pageURL: URL, schoolID: String) -> PageParseResult {
        let rules = CourseLeafRulePack.forSchoolID(schoolID)
        return PageParseResult(
            courses: parseCourses(from: xml, pageURL: pageURL, rules: rules),
            programs: parsePrograms(from: xml, pageURL: pageURL, rules: rules)
        )
    }

    static func crawlCatalog(
        baseURL rawURL: String,
        schoolID: String,
        parseRequirements: Bool = false
    ) async throws -> CrawlOutput {
        guard let baseURL = normalizeBaseURL(rawURL) else {
            throw ScraperError.invalidURL
        }
        let rulePack = CourseLeafRulePack.forSchoolID(schoolID)

        let pageURLs = try await sitemapPageURLs(baseURL: baseURL)

        var discoveredCourses: [CatalogCourse] = []
        var discoveredPrograms: [ScrapedProgram] = []
        var signatureMaterial: [String] = []
        signatureMaterial.reserveCapacity(pageURLs.count)

        for pageURL in pageURLs {
            let indexURL = normalizedIndexURL(from: pageURL)
            do {
                let xml = try await fetchXML(from: indexURL)
                signatureMaterial.append(indexURL.absoluteString)
                signatureMaterial.append(String(xml.prefix(4096)))
                discoveredCourses.append(contentsOf: parseCourses(from: xml, pageURL: pageURL, rules: rulePack))
                discoveredPrograms.append(
                    contentsOf: parsePrograms(
                        from: xml,
                        pageURL: pageURL,
                        rules: rulePack,
                        parseRequirements: parseRequirements,
                        schoolID: schoolID
                    )
                )
            } catch {
                continue
            }
        }

        let dedupedCourses = deduplicateCourses(discoveredCourses)
        let dedupedPrograms = deduplicatePrograms(discoveredPrograms)
        let signature = computeSignature(from: signatureMaterial, schoolID: schoolID)

        return CrawlOutput(
            courses: dedupedCourses,
            programs: dedupedPrograms,
            sourceSignature: signature
        )
    }

    static func normalizeBaseURL(_ rawURL: String) -> URL? {
        guard var components = URLComponents(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        if !components.path.hasSuffix("/") {
            components.path += "/"
        }
        return components.url
    }

    static func sitemapPageURLs(baseURL: URL) async throws -> [URL] {
        let sitemapURL = baseURL.appendingPathComponent("sitemap.xml")
        return try await discoverPageURLs(from: sitemapURL, fallbackBaseURL: baseURL)
    }

    private static func discoverPageURLs(from sitemapURL: URL, fallbackBaseURL: URL) async throws -> [URL] {
        let xml = try await fetchXML(from: sitemapURL)
        let locPattern = try NSRegularExpression(pattern: "<loc>(.*?)</loc>", options: [.caseInsensitive, .dotMatchesLineSeparators])
        let nsRange = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        let matches = locPattern.matches(in: xml, options: [], range: nsRange)

        var urls: [URL] = []
        urls.reserveCapacity(matches.count)
        for match in matches {
            guard let range = Range(match.range(at: 1), in: xml) else { continue }
            let raw = xml[range].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: raw), let host = url.host, host == fallbackBaseURL.host else { continue }
            urls.append(url)
        }

        if urls.isEmpty {
            return [fallbackBaseURL]
        }
        return Array(Set(urls)).sorted { $0.absoluteString < $1.absoluteString }
    }

    private static func fetchXML(from url: URL) async throws -> String {
        try await CourseLeafXMLClient.fetchXML(from: url)
    }

    private static func parseCourses(from xml: String, pageURL: URL, rules: CourseLeafRulePack) -> [CatalogCourse] {
        guard shouldParseCourses(pageURL: pageURL, rules: rules) else { return [] }
        guard xml.contains("<courseleaf") else { return [] }

        var courses: [CatalogCourse] = []
        for html in extractCDATAHTMLFragments(from: xml) {
            courses.append(contentsOf: parseCoursesFromHTML(html, pageURL: pageURL, rules: rules))
        }

        if courses.isEmpty {
            courses.append(contentsOf: parseCoursesLegacyFallback(from: xml, pageURL: pageURL, rules: rules))
        }
        return courses
    }

    private static func extractCDATAHTMLFragments(from xml: String) -> [String] {
        let pattern = try? NSRegularExpression(pattern: "<!\\[CDATA\\[(.*?)\\]\\]>", options: [.dotMatchesLineSeparators])
        let nsRange = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        guard let pattern else { return [] }
        return pattern.matches(in: xml, options: [], range: nsRange).compactMap { match in
            guard let range = Range(match.range(at: 1), in: xml) else { return nil }
            let html = String(xml[range])
            guard html.contains("courseblock") || html.contains("courseblocktitle") else { return nil }
            return html
        }
    }

    private static func parseCoursesFromHTML(_ html: String, pageURL: URL, rules: CourseLeafRulePack) -> [CatalogCourse] {
        guard let doc = try? SwiftSoup.parseBodyFragment(html) else { return [] }
        var courses: [CatalogCourse] = []

        if let blocks = try? doc.select("div.courseblock"), !blocks.isEmpty() {
            for block in blocks.array() {
                if let course = parseNYUStyleCourseBlock(block, pageURL: pageURL, rules: rules) {
                    courses.append(course)
                    continue
                }
                if let course = parseFordhamStyleCourseBlock(block, pageURL: pageURL, rules: rules) {
                    courses.append(course)
                }
            }
        }

        if let blocks = try? doc.select("dl.courseblock"), !blocks.isEmpty() {
            for block in blocks.array() {
                if let course = parseCMUStyleCourseBlock(block, pageURL: pageURL, rules: rules) {
                    courses.append(course)
                }
            }
        }

        return courses
    }

    private static func makeCourse(
        pageURL: URL,
        courseCode: String,
        title: String,
        description: String?,
        credits: Int,
        department: String?
    ) -> CatalogCourse {
        CatalogCourse(
            id: UUID(),
            courseCode: courseCode,
            title: title,
            description: description,
            credits: credits,
            department: department,
            prerequisites: nil,
            prerequisiteText: nil,
            corequisites: nil,
            typicallyOffered: nil,
            previewDetailURL: pageURL.absoluteString
        )
    }

    private static func parseNYUStyleCourseBlock(_ block: Element, pageURL: URL, rules: CourseLeafRulePack) -> CatalogCourse? {
        guard (try? block.select(".detail-code").first()) != nil else { return nil }
        let code = normalizedWhitespace((try? block.select(".detail-code").first()?.text()) ?? "")
        let title = normalizedWhitespace((try? block.select(".detail-title").first()?.text()) ?? "")
        let hoursLine = normalizedWhitespace((try? block.select(".detail-hours_html").first()?.text()) ?? "")
        guard !code.isEmpty else { return nil }

        let courseCode: String = {
            let trimmed = normalizedWhitespace(code)
            if trimmed.contains("-") && trimmed.split(separator: " ").count >= 2 {
                return trimmed
            }
            return normalizeCourseCode(trimmed, rules: rules)
        }()
        let credits = parseCredits(from: hoursLine, rules: rules)
        let description = normalizedWhitespace((try? block.select(".courseblockextra").first()?.text()) ?? "")
        let department = departmentFromCourseCode(courseCode, rules: rules)

        return makeCourse(
            pageURL: pageURL,
            courseCode: courseCode,
            title: title.isEmpty ? courseCode : title,
            description: description.isEmpty ? nil : description,
            credits: credits,
            department: department
        )
    }

    private static func parseFordhamStyleCourseBlock(_ block: Element, pageURL: URL, rules: CourseLeafRulePack) -> CatalogCourse? {
        let titleLine = normalizedWhitespace(
            (try? block.select("p.courseblocktitle, .courseblocktitle").first()?.text()) ?? ""
        )
        guard !titleLine.isEmpty else { return nil }
        guard (try? block.select(".detail-code").first()) == nil else { return nil }

        guard let parsed = parseFordhamTitleLine(titleLine) else { return nil }
        let description = normalizedWhitespace(
            (try? block.select("p.courseblockdesc, .courseblockdesc").first()?.text()) ?? ""
        )
        let courseCode = "\(parsed.dept) \(parsed.number)"

        return makeCourse(
            pageURL: pageURL,
            courseCode: courseCode,
            title: parsed.title,
            description: description.isEmpty ? nil : description,
            credits: parsed.credits,
            department: parsed.dept
        )
    }

    private static func parseCMUStyleCourseBlock(_ block: Element, pageURL: URL, rules: CourseLeafRulePack) -> CatalogCourse? {
        let titleLine = normalizedWhitespace((try? block.select("dt").first()?.text()) ?? "")
        let bodyLine = normalizedWhitespace((try? block.select("dd").first()?.text()) ?? "")
        guard !titleLine.isEmpty else { return nil }

        guard let parsed = parseCMUTitleLine(titleLine) else { return nil }
        let courseCode = "\(parsed.dept)-\(parsed.number)"
        let combinedText = "\(titleLine) \(bodyLine)"
        let credits = parseCredits(from: combinedText, rules: rules)

        return makeCourse(
            pageURL: pageURL,
            courseCode: courseCode,
            title: parsed.title,
            description: bodyLine.isEmpty ? nil : bodyLine,
            credits: credits,
            department: parsed.dept
        )
    }

    private struct FordhamTitleParts {
        let dept: String
        let number: String
        let title: String
        let credits: Int
    }

    private static func parseFordhamTitleLine(_ line: String) -> FordhamTitleParts? {
        let pattern = #"^([A-Z]{2,6})\s+([0-9]{4}[A-Z]?)\.\s+(.+?)\.\s+\((\d+(?:\.\d+)?)\s+Credits?\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: nsRange),
              let deptRange = Range(match.range(at: 1), in: line),
              let numberRange = Range(match.range(at: 2), in: line),
              let titleRange = Range(match.range(at: 3), in: line),
              let creditsRange = Range(match.range(at: 4), in: line) else {
            return nil
        }
        let credits = Double(line[creditsRange]).map { Int($0.rounded()) } ?? 0
        return FordhamTitleParts(
            dept: String(line[deptRange]).uppercased(),
            number: String(line[numberRange]).uppercased(),
            title: String(line[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines),
            credits: credits
        )
    }

    private struct CMUTitleParts {
        let dept: String
        let number: String
        let title: String
    }

    private static func parseCMUTitleLine(_ line: String) -> CMUTitleParts? {
        let pattern = #"^([0-9]{2})\s*[-–]\s*([0-9]{3}[A-Z]?)\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: nsRange),
              let deptRange = Range(match.range(at: 1), in: line),
              let numberRange = Range(match.range(at: 2), in: line),
              let titleRange = Range(match.range(at: 3), in: line) else {
            return nil
        }
        return CMUTitleParts(
            dept: String(line[deptRange]),
            number: String(line[numberRange]).uppercased(),
            title: String(line[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func parseCoursesLegacyFallback(from xml: String, pageURL: URL, rules: CourseLeafRulePack) -> [CatalogCourse] {
        let cdataPattern = rules.cdataHTMLPatterns.compactMap {
            try? NSRegularExpression(pattern: $0, options: [.dotMatchesLineSeparators])
        }
        let codePatterns = rules.courseCodePatterns.compactMap {
            try? NSRegularExpression(pattern: $0)
        }
        let nsRange = NSRange(xml.startIndex..<xml.endIndex, in: xml)

        var courses: [CatalogCourse] = []
        for cdataRegex in cdataPattern {
            for match in cdataRegex.matches(in: xml, options: [], range: nsRange) {
                guard let range = Range(match.range(at: 1), in: xml) else { continue }
                let html = String(xml[range])
                guard let doc = try? SwiftSoup.parseBodyFragment(html) else { continue }
                let text = normalizedWhitespace((try? doc.text()) ?? "")
                let textRange = NSRange(text.startIndex..<text.endIndex, in: text)

                var subjectRange: Range<String.Index>?
                var numberRange: Range<String.Index>?
                for codePattern in codePatterns {
                    if let codeMatch = codePattern.firstMatch(in: text, options: [], range: textRange),
                       let s = Range(codeMatch.range(at: 1), in: text),
                       let n = Range(codeMatch.range(at: 2), in: text) {
                        subjectRange = s
                        numberRange = n
                        break
                    }
                }
                guard let subjectRange, let numberRange else { continue }

                let dept = String(text[subjectRange])
                let number = String(text[numberRange])
                let usesHyphenCode = dept.allSatisfy(\.isNumber)
                let courseCode = usesHyphenCode ? "\(dept)-\(number)" : "\(dept) \(number)"
                let creditsValue = parseCredits(from: text, rules: rules)

                courses.append(makeCourse(
                    pageURL: pageURL,
                    courseCode: courseCode,
                    title: courseCode,
                    description: text.isEmpty ? nil : text,
                    credits: creditsValue,
                    department: dept
                ))
            }
        }
        return courses
    }

    /// Test entry: parse program metadata (+ optional requirements) from fixture `index.xml`.
    static func parseProgramsForTests(
        from xml: String,
        pageURL: URL,
        schoolID: String,
        parseRequirements: Bool
    ) -> [ScrapedProgram] {
        parsePrograms(
            from: xml,
            pageURL: pageURL,
            rules: CourseLeafRulePack.forSchoolID(schoolID),
            parseRequirements: parseRequirements,
            schoolID: schoolID
        )
    }

    private static func parsePrograms(
        from xml: String,
        pageURL: URL,
        rules: CourseLeafRulePack,
        parseRequirements: Bool = false,
        schoolID: String = ""
    ) -> [ScrapedProgram] {
        guard shouldParsePrograms(pageURL: pageURL, rules: rules) else {
            return []
        }
        guard xml.contains("<courseleaf") else { return [] }

        let titlePattern = try? NSRegularExpression(pattern: "<title>(.*?)</title>", options: [.caseInsensitive, .dotMatchesLineSeparators])
        let nsRange = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        let title: String = {
            guard let titleMatch = titlePattern?.firstMatch(in: xml, options: [], range: nsRange),
                  let range = Range(titleMatch.range(at: 1), in: xml) else {
                return pageURL.lastPathComponent.replacingOccurrences(of: "-", with: " ").capitalized
            }
            return String(xml[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }()

        if CourseLeafProgramURLParser.isJunkProgramTitle(title) {
            return []
        }

        let path = pageURL.path.lowercased()
        let lower = title.lowercased()
        let type: String = {
            if path.contains("/minor") || rules.minorKeywords.contains(where: { lower.contains($0) }) {
                return "Minor"
            }
            if path.contains("/major") || rules.majorKeywords.contains(where: { lower.contains($0) }) {
                return "Major"
            }
            if lower.contains("minor") { return "Minor" }
            if lower.contains("bachelor") || lower.contains("b.s") || lower.contains("b.a") || lower.contains("degree") {
                return "Major"
            }
            return "Major"
        }()

        let ownership = CourseLeafProgramURLParser.ownership(from: pageURL)
        let degreeType = CourseLeafProgramURLParser.degreeTypeFromTitle(title)
        let baseName = title.isEmpty ? pageURL.lastPathComponent : title

        var requirements: [DegreeRequirement]?
        if parseRequirements {
            if let parsed = try? CourseLeafRequirementsParser.parseRequirements(
                fromXML: xml,
                programURL: pageURL,
                schoolID: schoolID,
                degreeType: degreeType,
                programName: baseName
            ), !parsed.isEmpty {
                requirements = parsed
            }
        }

        var programs: [ScrapedProgram] = [
            ScrapedProgram(
                name: baseName,
                type: type,
                url: pageURL.absoluteString,
                department: ownership.department,
                college: ownership.college,
                degreeType: degreeType,
                requirements: requirements
            )
        ]

        if parseRequirements {
            let fragments = CourseLeafRequirementsParser.extractRequirementFragments(
                from: xml,
                schoolID: schoolID,
                programURL: pageURL,
                degreeType: degreeType
            )
            for variant in fragments.trackVariants {
                guard !variant.html.isEmpty else { continue }
                let wrapped = CourseLeafRequirementsParser.wrapHTMLFragment(variant.html)
                let rawTrack = (try? {
                    let doc = try SwiftSoup.parse(wrapped, pageURL.absoluteString)
                    return try CourseLeafCourselistHTMLParser.parse(doc: doc, logger: DebugLogger.shared)
                }()) ?? nil
                let trackRequirements = CourseLeafRequirementsParser.stampProgramMetadata(
                    rawTrack ?? [],
                    programName: "\(baseName) (\(variant.displayName))",
                    degreeType: degreeType,
                    programURL: pageURL
                )
                guard !trackRequirements.isEmpty else { continue }
                let trackURL = "\(pageURL.absoluteString)#track=\(variant.trackID)"
                let parentKey = pageURL.absoluteString
                programs.append(
                    ScrapedProgram(
                        name: "\(baseName) (\(variant.displayName))",
                        type: type,
                        url: trackURL,
                        department: ownership.department,
                        college: ownership.college,
                        degreeType: degreeType,
                        requirements: trackRequirements,
                        trackVariant: variant.trackID,
                        parentProgramURL: parentKey
                    )
                )
            }
        }

        return programs
    }

    private static func parseCredits(from text: String, rules: CourseLeafRulePack) -> Int {
        let patterns = rules.creditPatterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
        for pattern in patterns {
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = pattern.firstMatch(in: text, options: [], range: nsRange),
               let creditRange = Range(match.range(at: 1), in: text),
               let parsed = Double(text[creditRange]) {
                return Int(parsed.rounded())
            }
        }
        return 0
    }

    private static func normalizeCourseCode(_ raw: String, rules: CourseLeafRulePack) -> String {
        let normalized = normalizedWhitespace(raw)
        let patterns = rules.courseCodePatterns.compactMap { try? NSRegularExpression(pattern: $0) }
        let nsRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        for pattern in patterns {
            if let match = pattern.firstMatch(in: normalized, options: [], range: nsRange),
               let s = Range(match.range(at: 1), in: normalized),
               let n = Range(match.range(at: 2), in: normalized) {
                let dept = String(normalized[s])
                let number = String(normalized[n])
                if dept.allSatisfy(\.isNumber) {
                    return "\(dept)-\(number)"
                }
                return "\(dept) \(number)".replacingOccurrences(of: "  ", with: " ")
            }
        }
        return normalized
    }

    private static func departmentFromCourseCode(_ courseCode: String, rules: CourseLeafRulePack) -> String {
        if let hyphen = courseCode.firstIndex(of: "-") {
            return String(courseCode[..<hyphen])
        }
        return courseCode.split(separator: " ").first.map(String.init) ?? courseCode
    }

    private static func normalizedWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func deduplicateCourses(_ courses: [CatalogCourse]) -> [CatalogCourse] {
        var bestByCode: [String: CatalogCourse] = [:]
        for course in courses {
            let key = course.courseCode.uppercased()
            if let existing = bestByCode[key] {
                bestByCode[key] = preferredCourse(existing, course)
            } else {
                bestByCode[key] = course
            }
        }
        return bestByCode.values.sorted { $0.courseCode < $1.courseCode }
    }

    private static func preferredCourse(_ lhs: CatalogCourse, _ rhs: CatalogCourse) -> CatalogCourse {
        func score(_ course: CatalogCourse) -> Int {
            var value = 0
            if course.credits > 0 { value += 4 }
            if course.description != nil { value += 2 }
            if course.title.caseInsensitiveCompare(course.courseCode) != .orderedSame { value += 3 }
            return value
        }
        return score(rhs) > score(lhs) ? rhs : lhs
    }

    private static func deduplicatePrograms(_ programs: [ScrapedProgram]) -> [ScrapedProgram] {
        var seen = Set<String>()
        var output: [ScrapedProgram] = []
        output.reserveCapacity(programs.count)
        for program in programs {
            let key = "\(program.name.lowercased())|\(program.url.lowercased())"
            if seen.insert(key).inserted {
                output.append(program)
            }
        }
        return output
    }

    private static func computeSignature(from inputs: [String], schoolID: String) -> String {
        let payload = ([schoolID] + inputs.sorted()).joined(separator: "\n")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func shouldParseCourses(pageURL: URL, rules: CourseLeafRulePack) -> Bool {
        let path = pageURL.path.lowercased()
        return rules.coursePagePathHints.contains(where: { path.contains($0) })
    }

    private static func shouldParsePrograms(pageURL: URL, rules: CourseLeafRulePack) -> Bool {
        let path = pageURL.path.lowercased()
        return rules.programPagePathHints.contains(where: { path.contains($0) })
    }

    static func normalizedIndexURL(from pageURL: URL) -> URL {
        CourseLeafXMLClient.normalizedIndexURL(from: pageURL)
    }
}
