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

    private static let falsePositiveSubjects: Set<String> = [
        "ROOM", "FALL", "SPRING", "SUMMER", "WINTER", "CHAPTER", "PAGE", "SECTION", "VOLUME", "ISSUE", "STEP"
    ]

    static func extract(
        from classifiedBlocks: [CatalogPDFClassifiedBlock],
        minConfidence: Float,
        profile: CatalogPDFProfileData
    ) -> [CatalogCourse] {
        var byCode: [String: CatalogCourse] = [:]

        for classified in classifiedBlocks where classified.type == .course && classified.confidence >= minConfidence {
            let courses = parseCourses(from: classified.block.text, profile: profile)
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

    static func extractCourses(fromText text: String, profile: CatalogPDFProfileData) -> [CatalogCourse] {
        guard let codeRe = courseCodeRegex else { return [] }
        let normalized = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        var byCode: [String: CatalogCourse] = [:]
        let lines = normalized.components(separatedBy: .newlines)
        let useCMUStyle = CatalogPDFProfileLoader.supportsCMUStyleCourseCodes(profile)

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

            if useCMUStyle, let cmuRe = cmuCourseCodeRegex {
                for m in cmuRe.matches(in: line, range: nsRange) {
                    guard m.numberOfRanges >= 3,
                          let deptRange = Range(m.range(at: 1), in: line),
                          let numRange = Range(m.range(at: 2), in: line) else { continue }
                    let dept = String(line[deptRange])
                    let number = String(line[numRange])
                    guard !isLikelyFalsePositive(subject: dept, number: number, line: line) else { continue }
                    let code = "\(dept)-\(number)"
                    let (title, credits) = parseTitleAndCredits(afterCode: {
                        guard let codeRange = Range(m.range, in: line) else { return Substring(line) }
                        return line[codeRange.upperBound...]
                    }())
                    let course = CatalogCourse(
                        courseCode: code,
                        title: title.isEmpty ? code : title,
                        description: nil,
                        credits: credits,
                        department: dept,
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

    private static func parseCourses(from text: String, profile: CatalogPDFProfileData) -> [CatalogCourse] {
        extractCourses(fromText: text, profile: profile)
    }

    private static func courseFromMatch(_ m: NSTextCheckingResult, line: String) -> CatalogCourse? {
        guard m.numberOfRanges >= 3,
              let subjectRange = Range(m.range(at: 1), in: line),
              let numberRange = Range(m.range(at: 2), in: line) else {
            return nil
        }
        let subject = String(line[subjectRange])
        let number = String(line[numberRange])
        guard !isLikelyFalsePositive(subject: subject, number: number, line: line) else { return nil }

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

    private static func isLikelyFalsePositive(subject: String, number: String, line: String) -> Bool {
        let upperSubject = subject.uppercased()
        if falsePositiveSubjects.contains(upperSubject) { return true }
        if number.count == 4, let year = Int(number), (1900...2100).contains(year) { return true }
        let lower = line.lowercased()
        if lower.contains("chapter \(number.lowercased())") || lower.contains("page \(number.lowercased())") {
            return true
        }
        return false
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
                // CatalogCourse stores credits as Int; fractional values are rounded conservatively.
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
