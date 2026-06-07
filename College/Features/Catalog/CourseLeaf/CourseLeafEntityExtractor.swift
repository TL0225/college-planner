// CourseLeafEntityExtractor.swift
// Feature: Catalog
// Purpose: Shared CourseLeaf course-block extraction (NYU / Fordham / CMU / legacy).
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftSoup

enum CourseLeafEntityExtractor {
    static func makeCourse(
        pageURL: URL,
        courseCode: String,
        title: String,
        description: String?,
        credits: Int,
        department: String?,
        documentNodeID: UUID = UUID()
    ) -> CatalogCourse {
        CatalogCourse(
            id: documentNodeID,
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

    static func extractCoursesFromHTML(_ html: String, pageURL: URL, config: CourseLeafProfileConfig) -> [CatalogCourse] {
        guard let doc = try? SwiftSoup.parseBodyFragment(html) else { return [] }
        var courses: [CatalogCourse] = []

        if let blocks = try? doc.select("div.courseblock"), !blocks.isEmpty() {
            for block in blocks.array() {
                if let course = parseNYUStyleCourseBlock(block, pageURL: pageURL, config: config) {
                    courses.append(course)
                    continue
                }
                if let course = parseFordhamStyleCourseBlock(block, pageURL: pageURL, config: config) {
                    courses.append(course)
                }
            }
        }

        if let blocks = try? doc.select("dl.courseblock"), !blocks.isEmpty() {
            for block in blocks.array() {
                if let course = parseCMUStyleCourseBlock(block, pageURL: pageURL, config: config) {
                    courses.append(course)
                }
            }
        }

        return courses
    }

    static func extractNYUCoursesFromHTML(_ html: String, pageURL: URL, config: CourseLeafProfileConfig) -> [CatalogCourse] {
        guard let doc = try? SwiftSoup.parseBodyFragment(html) else { return [] }
        var courses: [CatalogCourse] = []
        guard let blocks = try? doc.select("div.courseblock"), !blocks.isEmpty() else { return [] }
        for block in blocks.array() {
            if let course = parseNYUStyleCourseBlock(block, pageURL: pageURL, config: config) {
                courses.append(course)
            }
        }
        return courses
    }

    static func extractFordhamCoursesFromHTML(_ html: String, pageURL: URL, config: CourseLeafProfileConfig) -> [CatalogCourse] {
        guard let doc = try? SwiftSoup.parseBodyFragment(html) else { return [] }
        var courses: [CatalogCourse] = []
        guard let blocks = try? doc.select("div.courseblock"), !blocks.isEmpty() else { return [] }
        for block in blocks.array() {
            if let course = parseFordhamStyleCourseBlock(block, pageURL: pageURL, config: config) {
                courses.append(course)
            }
        }
        return courses
    }

    static func extractCMUCoursesFromHTML(_ html: String, pageURL: URL, config: CourseLeafProfileConfig) -> [CatalogCourse] {
        guard let doc = try? SwiftSoup.parseBodyFragment(html) else { return [] }
        var courses: [CatalogCourse] = []
        guard let blocks = try? doc.select("dl.courseblock"), !blocks.isEmpty() else { return [] }
        for block in blocks.array() {
            if let course = parseCMUStyleCourseBlock(block, pageURL: pageURL, config: config) {
                courses.append(course)
            }
        }
        return courses
    }

    static func extractCoursesLegacyFallback(from xml: String, pageURL: URL, config: CourseLeafProfileConfig) -> [CatalogCourse] {
        let cdataPattern = config.cdataHTMLPatterns.compactMap {
            try? NSRegularExpression(pattern: $0, options: [.dotMatchesLineSeparators])
        }
        let codePatterns = config.courseCodePatterns.compactMap {
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
                let creditsValue = parseCredits(from: text, config: config)

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

    static func parseNYUStyleCourseBlock(_ block: Element, pageURL: URL, config: CourseLeafProfileConfig) -> CatalogCourse? {
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
            return normalizeCourseCode(trimmed, config: config)
        }()
        let credits = parseCredits(from: hoursLine, config: config)
        let description = normalizedWhitespace((try? block.select(".courseblockextra").first()?.text()) ?? "")
        let department = departmentFromCourseCode(courseCode, config: config)

        return makeCourse(
            pageURL: pageURL,
            courseCode: courseCode,
            title: title.isEmpty ? courseCode : title,
            description: description.isEmpty ? nil : description,
            credits: credits,
            department: department
        )
    }

    static func parseFordhamStyleCourseBlock(_ block: Element, pageURL: URL, config: CourseLeafProfileConfig) -> CatalogCourse? {
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

    static func parseCMUStyleCourseBlock(_ block: Element, pageURL: URL, config: CourseLeafProfileConfig) -> CatalogCourse? {
        let titleLine = normalizedWhitespace((try? block.select("dt").first()?.text()) ?? "")
        let bodyLine = normalizedWhitespace((try? block.select("dd").first()?.text()) ?? "")
        guard !titleLine.isEmpty else { return nil }

        guard let parsed = parseCMUTitleLine(titleLine) else { return nil }
        let courseCode = "\(parsed.dept)-\(parsed.number)"
        let combinedText = "\(titleLine) \(bodyLine)"
        let credits = parseCredits(from: combinedText, config: config)

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

    static func parseCredits(from text: String, config: CourseLeafProfileConfig) -> Int {
        let patterns = config.creditPatterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
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

    static func normalizeCourseCode(_ raw: String, config: CourseLeafProfileConfig) -> String {
        let normalized = normalizedWhitespace(raw)
        let patterns = config.courseCodePatterns.compactMap { try? NSRegularExpression(pattern: $0) }
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

    static func departmentFromCourseCode(_ courseCode: String, config: CourseLeafProfileConfig) -> String {
        if let hyphen = courseCode.firstIndex(of: "-") {
            return String(courseCode[..<hyphen])
        }
        return courseCode.split(separator: " ").first.map(String.init) ?? courseCode
    }

    static func normalizedWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
