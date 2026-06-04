// CatalogPDFCourseExtractor.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogPDFCourseExtractor.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Stage 4 recognition: courses from classified blocks only.
enum CatalogPDFCourseExtractor {
    private static let courseCodeRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"\b([A-Z]{2,6})\s*[-–]?\s*([0-9]{2,4})\b"#,
        options: []
    )

    private static let cmuCourseCodeRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"\b([0-9]{2})[-–]([0-9]{3})\b"#,
        options: []
    )

    private static let creditsRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"\b(\d+(?:\.\d+)?)\s*(credits?|units?)\b"#,
        options: [.caseInsensitive]
    )

    static func extract(
        from classifiedBlocks: [CatalogPDFClassifiedBlock],
        minConfidence: Float
    ) -> [CatalogCourse] {
        var byCode: [String: CatalogCourse] = [:]

        for classified in classifiedBlocks where classified.type == .course && classified.confidence >= minConfidence {
            let courses = parseCourses(from: classified.block.text)
            for course in courses {
                if let existing = byCode[course.courseCode] {
                    if course.title.count > existing.title.count {
                        byCode[course.courseCode] = course
                    }
                } else {
                    byCode[course.courseCode] = course
                }
            }
        }

        return byCode.values.sorted { $0.courseCode < $1.courseCode }
    }

  static func extractCourses(fromText text: String) -> [CatalogCourse] {
        guard let codeRe = courseCodeRegex else { return [] }
        let normalized = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        var byCode: [String: CatalogCourse] = [:]
        let lines = normalized.components(separatedBy: .newlines)

        for rawLine in lines {
            let line = rawLine
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
            for m in codeRe.matches(in: line, range: nsRange) {
                guard let course = courseFromMatch(m, line: line) else { continue }
                if let existing = byCode[course.courseCode] {
                    if course.title.count > existing.title.count { byCode[course.courseCode] = course }
                } else {
                    byCode[course.courseCode] = course
                }
            }

            if let cmuRe = cmuCourseCodeRegex {
                for m in cmuRe.matches(in: line, range: nsRange) {
                    guard m.numberOfRanges >= 3,
                          let deptRange = Range(m.range(at: 1), in: line),
                          let numRange = Range(m.range(at: 2), in: line) else { continue }
                    let code = "\(line[deptRange])-\(line[numRange])"
                    let (title, credits) = parseTitleAndCredits(afterCode: {
                        guard let codeRange = Range(m.range, in: line) else { return Substring(line) }
                        return line[codeRange.upperBound...]
                    }())
                    let course = CatalogCourse(
                        courseCode: code,
                        title: title.isEmpty ? code : title,
                        description: nil,
                        credits: credits,
                        department: String(line[deptRange]),
                        prerequisites: nil,
                        prerequisiteText: nil,
                        corequisites: nil,
                        typicallyOffered: nil
                    )
                    if let existing = byCode[code] {
                        if course.title.count > existing.title.count { byCode[code] = course }
                    } else {
                        byCode[code] = course
                    }
                }
            }
        }

        return byCode.values.sorted { $0.courseCode < $1.courseCode }
    }

    private static func parseCourses(from text: String) -> [CatalogCourse] {
        extractCourses(fromText: text)
    }

    private static func courseFromMatch(_ m: NSTextCheckingResult, line: String) -> CatalogCourse? {
        guard m.numberOfRanges >= 3,
              let subjectRange = Range(m.range(at: 1), in: line),
              let numberRange = Range(m.range(at: 2), in: line) else {
            return nil
        }
        let subject = String(line[subjectRange])
        let number = String(line[numberRange])
        let normalizedCode = "\(subject) \(number)".uppercased()
        let afterCode: Substring = {
            guard let codeRange = Range(m.range, in: line) else { return Substring(line) }
            return line[codeRange.upperBound...]
        }()
        let (title, credits) = parseTitleAndCredits(afterCode: afterCode)
        return CatalogCourse(
            courseCode: normalizedCode,
            title: title.isEmpty ? normalizedCode : title,
            description: nil,
            credits: credits,
            department: subject.isEmpty ? nil : subject,
            prerequisites: nil,
            prerequisiteText: nil,
            corequisites: nil,
            typicallyOffered: nil
        )
    }

    private static func parseTitleAndCredits(afterCode: Substring) -> (title: String, credits: Int) {
        let cleaned = String(afterCode).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return ("", 0) }

        if let creditsRe = creditsRegex {
            let ns = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            if let m = creditsRe.firstMatch(in: cleaned, range: ns),
               m.numberOfRanges >= 2,
               let creditValueRange = Range(m.range(at: 1), in: cleaned) {
                let creditDouble = Double(String(cleaned[creditValueRange])) ?? 0
                let creditInt = Int(creditDouble.rounded())
                let titlePart = cleaned[..<(Range(m.range, in: cleaned)?.lowerBound ?? cleaned.startIndex)]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let title = titlePart
                    .replacingOccurrences(of: "[-–—:.;]+\\s*$", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return (title: title.isEmpty ? cleaned : title, credits: max(0, creditInt))
            }
        }

        return (title: cleaned, credits: 0)
    }
}
