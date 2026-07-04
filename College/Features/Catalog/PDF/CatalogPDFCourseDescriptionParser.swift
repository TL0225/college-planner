// CatalogPDFCourseDescriptionParser.swift
// Feature: Catalog
// Purpose: Grammar-driven block parser for catalog course-description sections.

import Foundation

/// Parses the "Course Descriptions" section of a catalog PDF into structured courses.
///
/// Uses an adaptive `CourseEntryGrammar` (header + metadata + body) rather than a single
/// hard-coded CourseLeaf format. When no grammar is supplied, detection runs automatically.
enum CatalogPDFCourseDescriptionParser {
    private static let courseCodeRefRegex = try? NSRegularExpression(
        pattern: #"\b([A-Z]{2,6})\s+(\d{3,4}[A-Z]?)\b"#
    )

    private static let numNumCodeRefRegex = try? NSRegularExpression(
        pattern: #"\b(\d{2})-(\d{3})\b"#
    )

    static func parse(sectionText: String, grammar: CatalogPDFCourseEntryGrammar? = nil) -> [CatalogCourse] {
        parseWithDiagnostics(sectionText: sectionText, grammar: grammar).courses
    }

    static func parseWithDiagnostics(
        sectionText: String,
        grammar explicitGrammar: CatalogPDFCourseEntryGrammar? = nil,
        profileHints: CatalogPDFProfileData? = nil
    ) -> (courses: [CatalogCourse], detection: CatalogPDFCourseFormatDetectionResult, failedHeaders: [String]) {
        let detection = explicitGrammar.map {
            CatalogPDFCourseFormatDetectionResult(
                grammar: $0,
                confidence: 1,
                sampleSize: 0,
                evidence: ["explicit": 1]
            )
        } ?? CatalogPDFCourseFormatDetector.detect(sectionText: sectionText, profileHints: profileHints)

        let (courses, failedHeaders) = parseBlocks(sectionText: sectionText, grammar: detection.grammar)
        return (courses, detection, failedHeaders)
    }

    static func parseBlocks(
        sectionText: String,
        grammar: CatalogPDFCourseEntryGrammar
    ) -> (courses: [CatalogCourse], failedHeaders: [String]) {
        let normalized = sectionText.replacingOccurrences(of: "\u{00A0}", with: " ")
        let rawLines = normalized.components(separatedBy: .newlines)

        var byCode: [String: CatalogCourse] = [:]
        var order: [String] = []
        var builder: CourseBuilder?
        var failedHeaders: [String] = []

        func finalize(recordFailure reason: String? = nil) {
            if let reason, builder != nil {
                failedHeaders.append(reason)
            }
            guard let course = builder?.build() else { builder = nil; return }
            if let existing = byCode[course.courseCode] {
                if preferred(course, over: existing) {
                    byCode[course.courseCode] = course
                }
            } else {
                byCode[course.courseCode] = course
                order.append(course.courseCode)
            }
            builder = nil
        }

        for rawLine in rawLines {
            let line = rawLine
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if let header = matchHeader(line, grammar: grammar.header) {
                finalize()
                builder = CourseBuilder(header: header, grammar: grammar)
                if grammar.metadata == .inlineParenthetical,
                   let credits = CatalogPDFCourseFormatDetector.extractCredits(from: line, metadata: .inlineParenthetical) {
                    builder?.setCredits(credits)
                    builder?.finalizeTitleFromBuffer()
                } else if grammar.header.codeShape == .numNum,
                          !header.titleFragment.isEmpty,
                          let stripped = CatalogPDFCourseFormatDetector.extractTrailingUnits(from: header.titleFragment) {
                    builder?.applyTrailingUnitsTitle(stripped.title, credits: stripped.credits)
                }
                continue
            }

            guard let current = builder else { continue }

            if current.awaitingMetadata {
                if grammar.metadata == .nextLineHoursCredits,
                   current.consumeHoursCreditsMetadata(line) {
                    continue
                }

                if grammar.metadata == .inlineParenthetical,
                   let credits = CatalogPDFCourseFormatDetector.extractCredits(from: current.titleBuffer, metadata: .inlineParenthetical) {
                    current.setCredits(credits)
                    current.finalizeTitleFromBuffer()
                    continue
                }

                if CatalogPDFCourseFormatDetector.lineLooksLikeMetadata(line, metadata: grammar.metadata) {
                    if let credits = CatalogPDFCourseFormatDetector.extractCredits(from: line, metadata: grammar.metadata) {
                        current.setCredits(credits)
                    }
                    current.finalizeTitleFromBuffer()
                    continue
                }

                if grammar.header.codeShape == .numNum,
                   isTermOnlyMetadataPrefix(line) {
                    continue
                }

                if grammar.header.codeShape == .numNum,
                   CatalogPDFCourseFormatDetector.lineLooksLikeMetadata(line, metadata: .nextLineTermUnits),
                   let credits = CatalogPDFCourseFormatDetector.extractCredits(from: line, metadata: .nextLineTermUnits) {
                    current.setCredits(credits)
                    current.finalizeTitleFromBuffer()
                    continue
                }

                if current.canContinueTitle(with: line, grammar: grammar) {
                    current.appendTitleFragment(line)
                    if grammar.metadata == .inlineParenthetical,
                       let credits = CatalogPDFCourseFormatDetector.extractCredits(from: current.titleBuffer, metadata: .inlineParenthetical) {
                        current.setCredits(credits)
                        current.finalizeTitleFromBuffer()
                    }
                    continue
                }

                finalize(recordFailure: "metadata_unresolved:\(current.courseCode)")
                if let header = matchHeader(line, grammar: grammar.header) {
                    builder = CourseBuilder(header: header, grammar: grammar)
                }
                continue
            }

            if isNoise(line) { continue }

            if let prereq = strip(prefixes: ["Prerequisites:", "Prerequisite:", "Pre-requisites:", "Pre-requisite:"], from: line) {
                current.appendPrerequisite(prereq)
            } else if let coreq = strip(prefixes: ["Corequisites:", "Corequisite:", "Co-requisites:", "Co-requisite:"], from: line) {
                current.appendCorequisite(coreq)
            } else if strip(prefixes: ["Attributes:", "Attribute:"], from: line) != nil {
                continue
            } else if current.collectingPrerequisite {
                current.appendPrerequisite(line)
            } else if current.collectingCorequisite {
                current.appendCorequisite(line)
            } else {
                current.appendDescription(line)
            }
        }
        finalize()

        return (order.compactMap { byCode[$0] }, failedHeaders)
    }

    // MARK: - Header matching

    struct ParsedHeader {
        let courseCode: String
        let department: String
        let titleFragment: String
    }

    static func matchHeader(_ line: String, grammar: CatalogPDFHeaderGrammar) -> ParsedHeader? {
        if let match = regexMatch(pattern: grammar.headerPattern, in: line, groups: 3) {
            let subject = match[0]
            let number = match[1]
            let rest = match[2]
            return ParsedHeader(
                courseCode: formatCode(subject: subject, number: number, shape: grammar.codeShape),
                department: subject,
                titleFragment: rest
            )
        }

        if grammar.codeShape == .numNum,
           grammar.allowsSplitCodeLine,
           let match = regexMatch(pattern: CatalogPDFHeaderGrammar.numNumSplitPattern, in: line, groups: 2) {
            return ParsedHeader(
                courseCode: "\(match[0])-\(match[1])",
                department: match[0],
                titleFragment: ""
            )
        }

        return nil
    }

    private static func formatCode(subject: String, number: String, shape: CatalogPDFHeaderCodeShape) -> String {
        switch shape {
        case .numNum:
            return "\(subject)-\(number)"
        default:
            return "\(subject) \(number)".uppercased()
        }
    }

    private static func regexMatch(pattern: String, in line: String, groups: Int) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range), match.numberOfRanges >= groups + 1 else {
            return nil
        }
        var captured: [String] = []
        for idx in 1...groups {
            guard let r = Range(match.range(at: idx), in: line) else { return nil }
            captured.append(String(line[r]))
        }
        return captured
    }

    private static func isTermOnlyMetadataPrefix(_ line: String) -> Bool {
        line.range(
            of: #"^(?i)(all semesters|fall and spring|fall|spring|summer|intermittent|winter)$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isNoise(_ line: String) -> Bool {
        if line.count == 1 { return true }
        if line.range(of: #"\(p\.\s*\d+\)"#, options: .regularExpression) != nil { return true }
        if line.range(of: #"^[A-Z][\w ,&/()'.-]*\([A-Z]{2,6}\)$"#, options: .regularExpression) != nil { return true }
        if line.hasPrefix("Updated:") { return true }
        if line.range(of: #"^\d{1,4}$"#, options: .regularExpression) != nil { return true }
        if line.range(of: #"^Full Academic Bulletin\b"#, options: .regularExpression) != nil { return true }
        if line.range(of: #"^\d+\s+[A-Z][\w ,&/()'.-]*\([A-Z]{2,6}\)$"#, options: .regularExpression) != nil { return true }
        if line.range(of: #"^\d{1,4}\s+[A-Z][A-Za-z]"#, options: .regularExpression) != nil,
           line.range(of: #"\([A-Z]{2,6}\)"#, options: .regularExpression) != nil { return true }
        if line == "TBD" { return true }
        if line.hasPrefix("Course Website:") { return true }
        return false
    }

    /// Running-header / page-break noise injected mid-entry by pagination
    /// (e.g. `Programs and Courses of Instruction`, `Classics 179`).
    static func isPaginationNoise(_ line: String) -> Bool {
        if line.contains("Programs and Courses of Instruction") { return true }
        if line.range(of: #"^[A-Z][A-Za-z &,'\-/]+\s+\d{1,4}$"#, options: .regularExpression) != nil { return true }
        return false
    }

    private static func strip(prefixes: [String], from line: String) -> String? {
        for prefix in prefixes where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func preferred(_ candidate: CatalogCourse, over existing: CatalogCourse) -> Bool {
        let candidateScore = (candidate.description?.count ?? 0) + candidate.title.count + (candidate.credits > 0 ? 10 : 0)
        let existingScore = (existing.description?.count ?? 0) + existing.title.count + (existing.credits > 0 ? 10 : 0)
        return candidateScore > existingScore
    }

    // MARK: - Course builder

    private final class CourseBuilder {
        let courseCode: String
        let department: String
        private let grammar: CatalogPDFCourseEntryGrammar
        private(set) var awaitingMetadata: Bool
        private(set) var collectingPrerequisite = false
        private(set) var collectingCorequisite = false

        private(set) var titleBuffer = ""
        private var titleContinuationCount = 0
        private var metadataBuffer = ""
        private var metadataLineCount = 0
        private var accumulatingMetadata = false
        private var title = ""
        private var credits = 0
        private var descriptionLines: [String] = []
        private var prerequisiteText = ""
        private var corequisiteText = ""

        init(header: ParsedHeader, grammar: CatalogPDFCourseEntryGrammar) {
            self.courseCode = header.courseCode
            self.department = header.department
            self.grammar = grammar
            self.awaitingMetadata = true
            if !header.titleFragment.isEmpty {
                titleBuffer = header.titleFragment
            }
        }

        func appendTitleFragment(_ text: String) {
            if !titleBuffer.isEmpty {
                titleBuffer += " "
                titleContinuationCount += 1
            }
            titleBuffer += text
        }

        func finalizeTitleFromBuffer() {
            if grammar.metadata == .inlineParenthetical,
               let parsed = extractInlineTitleAndCredits(from: titleBuffer) {
                title = parsed.title
                if credits == 0 { credits = parsed.credits }
            } else {
                title = cleanTitle(titleBuffer)
            }
            awaitingMetadata = false
        }

        func setCredits(_ value: Int) {
            credits = max(0, value)
        }

        func applyTrailingUnitsTitle(_ title: String, credits: Int) {
            titleBuffer = title
            setCredits(credits)
            finalizeTitleFromBuffer()
        }

        /// Consumes a Brooklyn-style `N hours; N credits` metadata block that may wrap
        /// across multiple lines. Returns true when the line was absorbed as metadata.
        ///
        /// The credit value frequently lands a line or two below the hours clause (or is
        /// split as `…; 3` + `credits`), so once a block opens we accumulate continuation
        /// lines until the credit resolves, a new header appears, or a short cap is hit.
        func consumeHoursCreditsMetadata(_ line: String) -> Bool {
            if CatalogPDFCourseDescriptionParser.matchHeader(line, grammar: grammar.header) != nil {
                if accumulatingMetadata {
                    finalizeTitleFromBuffer()
                    accumulatingMetadata = false
                }
                return false
            }

            if accumulatingMetadata {
                if CatalogPDFCourseDescriptionParser.isPaginationNoise(line) { return true }
                metadataBuffer += " " + line
                metadataLineCount += 1
                if let credits = CatalogPDFCourseFormatDetector.creditsFromHoursCreditsBuffer(metadataBuffer) {
                    setCredits(credits)
                    finalizeTitleFromBuffer()
                    accumulatingMetadata = false
                } else if metadataLineCount >= 3 {
                    finalizeTitleFromBuffer()
                    accumulatingMetadata = false
                }
                return true
            }

            guard CatalogPDFCourseFormatDetector.lineBeginsHoursCreditsBlock(line) else { return false }

            accumulatingMetadata = true
            metadataBuffer = line
            metadataLineCount = 1
            if let credits = CatalogPDFCourseFormatDetector.creditsFromHoursCreditsBuffer(metadataBuffer) {
                setCredits(credits)
                finalizeTitleFromBuffer()
                accumulatingMetadata = false
            }
            return true
        }

        func canContinueTitle(with line: String, grammar: CatalogPDFCourseEntryGrammar) -> Bool {
            if titleContinuationCount >= grammar.header.maxTitleContinuationLines { return false }
            if matchHeader(line, grammar: grammar.header) != nil { return false }
            if CatalogPDFCourseFormatDetector.lineLooksLikeMetadata(line, metadata: grammar.metadata) { return false }
            if strip(prefixes: ["Prerequisites:", "Prerequisite:", "Corequisites:", "Corequisite:"], from: line) != nil {
                return false
            }
            return true
        }

        func appendDescription(_ line: String) {
            collectingPrerequisite = false
            collectingCorequisite = false
            descriptionLines.append(line)
        }

        func appendPrerequisite(_ text: String) {
            collectingPrerequisite = true
            collectingCorequisite = false
            prerequisiteText = prerequisiteText.isEmpty ? text : prerequisiteText + " " + text
        }

        func appendCorequisite(_ text: String) {
            collectingCorequisite = true
            collectingPrerequisite = false
            corequisiteText = corequisiteText.isEmpty ? text : corequisiteText + " " + text
        }

        func build() -> CatalogCourse? {
            if title.isEmpty {
                if grammar.metadata == .inlineParenthetical,
                   let parsed = extractInlineTitleAndCredits(from: titleBuffer) {
                    title = parsed.title
                    if credits == 0 { credits = parsed.credits }
                } else {
                    title = cleanTitle(titleBuffer)
                }
            }

            let cleanedTitle = title.isEmpty ? courseCode : title
            let description = descriptionLines
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let prereqRaw = prerequisiteText.trimmingCharacters(in: .whitespacesAndNewlines)
            let coreqRaw = corequisiteText.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !isStructuralShell(title: cleanedTitle, description: description, credits: credits) else {
                return nil
            }

            return CatalogCourse(
                courseCode: courseCode,
                title: cleanedTitle,
                description: description.isEmpty ? nil : description,
                credits: max(0, credits),
                department: department,
                prerequisites: prereqRaw.isEmpty ? nil : structuredPrerequisite(from: prereqRaw),
                prerequisiteText: prereqRaw.isEmpty ? nil : prereqRaw,
                corequisites: courseCodes(in: coreqRaw),
                typicallyOffered: nil
            )
        }

        private func extractInlineTitleAndCredits(from headerBody: String) -> (title: String, credits: Int)? {
            guard let credits = CatalogPDFCourseFormatDetector.extractCredits(from: headerBody, metadata: .inlineParenthetical) else {
                return nil
            }
            let pattern = #"\(\s*(\d+(?:\.\d+)?)(?:\s*(?:to|or|-|–|—)\s*(\d+(?:\.\d+)?))?\s*[Cc]redits?\s*\)"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
                  let match = regex.firstMatch(in: headerBody, range: NSRange(headerBody.startIndex..<headerBody.endIndex, in: headerBody)),
                  let tokenRange = Range(match.range, in: headerBody) else {
                return (cleanTitle(headerBody), credits)
            }
            let titlePart = String(headerBody[..<tokenRange.lowerBound])
            return (cleanTitle(titlePart), credits)
        }

        private func isStructuralShell(title: String, description: String, credits: Int) -> Bool {
            guard credits == 0, description.isEmpty else { return false }
            if title == courseCode { return true }
            if title.hasPrefix("•") { return true }
            if title.range(of: #"^\d+\s+.+\s+Courses$"#, options: .regularExpression) != nil { return true }
            return false
        }
    }

    // MARK: - Title / prerequisite helpers

    static func extractTitleAndCredits(from headerBody: String) -> (title: String, credits: Int)? {
        guard let credits = CatalogPDFCourseFormatDetector.extractCredits(from: headerBody, metadata: .inlineParenthetical) else {
            return nil
        }
        let pattern = #"\(\s*(\d+(?:\.\d+)?)(?:\s*(?:to|or|-|–|—)\s*(\d+(?:\.\d+)?))?\s*[Cc]redits?\s*\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: headerBody, range: NSRange(headerBody.startIndex..<headerBody.endIndex, in: headerBody)),
              let tokenRange = Range(match.range, in: headerBody) else {
            return (cleanTitle(headerBody), credits)
        }
        return (cleanTitle(String(headerBody[..<tokenRange.lowerBound])), credits)
    }

    static func cleanTitle(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[\\s.:;,–—-]+$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func structuredPrerequisite(from text: String) -> PrerequisiteRule? {
        let codes = courseCodes(in: text) ?? []
        guard codes.count >= 1 else { return nil }
        if codes.count == 1 {
            return .course(CourseRequirement(courseCode: codes[0], minGrade: nil))
        }

        let lowered = " " + text.lowercased() + " "
        let hasOr = lowered.contains(" or ")
        let hasAnd = lowered.contains(" and ") || text.contains(",")
        let rules = codes.map { PrerequisiteRule.course(CourseRequirement(courseCode: $0, minGrade: nil)) }

        if hasOr && !hasAnd { return .or(rules) }
        if hasAnd && !hasOr { return .and(rules) }
        return nil
    }

    static func courseCodes(in text: String) -> [String]? {
        var codes: [String] = []
        var seen: Set<String> = []

        if let regex = courseCodeRefRegex {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for m in regex.matches(in: text, range: range) {
                guard m.numberOfRanges >= 3,
                      let subjRange = Range(m.range(at: 1), in: text),
                      let numRange = Range(m.range(at: 2), in: text) else { continue }
                let code = "\(text[subjRange]) \(text[numRange])".uppercased()
                if seen.insert(code).inserted { codes.append(code) }
            }
        }

        if let regex = numNumCodeRefRegex {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for m in regex.matches(in: text, range: range) {
                guard m.numberOfRanges >= 3,
                      let a = Range(m.range(at: 1), in: text),
                      let b = Range(m.range(at: 2), in: text) else { continue }
                let code = "\(text[a])-\(text[b])"
                if seen.insert(code).inserted { codes.append(code) }
            }
        }

        return codes.isEmpty ? nil : codes
    }
}
