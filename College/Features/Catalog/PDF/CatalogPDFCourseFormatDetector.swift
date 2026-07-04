// CatalogPDFCourseFormatDetector.swift
// Feature: Catalog
// Purpose: Detect course-entry grammar from catalog PDF text via frequency scoring.

import Foundation
import PDFKit

enum CatalogPDFCourseFormatDetector {
    /// Below this threshold the pipeline uses the legacy extractor instead of adaptive parsing.
    static let confidenceThreshold = 0.80

    /// Minimum line-start header matches required before trusting detection.
    static let minimumSampleSize = 25

    static func detect(
        sectionText: String,
        profileHints: CatalogPDFProfileData? = nil
    ) -> CatalogPDFCourseFormatDetectionResult {
        let lines = normalizedLines(from: sectionText)
        guard !lines.isEmpty else {
            return fallbackResult(preferredCodeShape: preferredCodeShape(from: profileHints))
        }

        var headerScores: [CatalogPDFHeaderCodeShape: Int] = [:]
        var headerLineIndices: [CatalogPDFHeaderCodeShape: [Int]] = [:]

        for (index, line) in lines.enumerated() {
            if let shape = matchHeaderCodeShape(on: line) {
                headerScores[shape, default: 0] += 1
                headerLineIndices[shape, default: []].append(index)
            }
        }

        let preferredShape = preferredCodeShape(from: profileHints)
        let rankedHeaders = rankScores(headerScores, preferred: preferredShape)
        let winnerHeader = rankedHeaders.first?.key ?? preferredShape ?? .alphaNumDot
        let winnerHeaderCount = rankedHeaders.first?.value ?? 0
        let runnerUpHeaderCount = rankedHeaders.dropFirst().first?.value ?? 0

        let metadata = detectMetadataGrammar(
            lines: lines,
            headerShape: winnerHeader,
            headerLineIndices: headerLineIndices[winnerHeader] ?? []
        )

        let grammar = CatalogPDFCourseEntryGrammar(
            header: CatalogPDFHeaderGrammar.builtin(for: winnerHeader),
            metadata: metadata
        )

        let confidence = scoreConfidence(
            winnerCount: winnerHeaderCount,
            runnerUpCount: runnerUpHeaderCount,
            sampleSize: winnerHeaderCount
        )

        var evidence: [String: Int] = [:]
        evidence[grammar.identifier] = winnerHeaderCount
        for (shape, count) in headerScores where shape != winnerHeader {
            evidence["header:\(shape.rawValue)"] = count
        }

        return CatalogPDFCourseFormatDetectionResult(
            grammar: grammar,
            confidence: confidence,
            sampleSize: winnerHeaderCount,
            evidence: evidence
        )
    }

    // MARK: - Section assistance (code density)

    /// Scans each page for dominant course-code line starts. Used to infer course-description regions.
    static func codeDensityByPage(document: PDFDocument) -> [(pageIndex: Int, count: Int, dominantShape: CatalogPDFHeaderCodeShape?)] {
        var out: [(pageIndex: Int, count: Int, dominantShape: CatalogPDFHeaderCodeShape?)] = []
        out.reserveCapacity(document.pageCount)

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let lines = normalizedLines(from: page.string ?? "")
            var shapeCounts: [CatalogPDFHeaderCodeShape: Int] = [:]
            var total = 0
            for line in lines {
                if let shape = matchHeaderCodeShape(on: line) {
                    shapeCounts[shape, default: 0] += 1
                    total += 1
                } else if line.range(of: CatalogPDFHeaderGrammar.numNumSplitPattern, options: .regularExpression) != nil {
                    shapeCounts[.numNum, default: 0] += 1
                    total += 1
                }
            }
            let dominant = shapeCounts.max(by: { $0.value < $1.value })?.key
            out.append((pageIndex: pageIndex, count: total, dominantShape: dominant))
        }
        return out
    }

    /// Per-page count of course headers that are followed by a prose description.
    ///
    /// Unlike `codeDensityByPage` (which counts bare header lines and therefore also
    /// lights up requirement/program tables full of cross-referenced codes), this only
    /// counts headers followed within a few lines by a real sentence. That distinguishes
    /// true course-description pages from listing pages, so it can safely drive
    /// course-section boundary expansion without swallowing requirement sections.
    static func describedHeaderDensityByPage(document: PDFDocument) -> [Int] {
        var out = [Int](repeating: 0, count: document.pageCount)
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let lines = normalizedLines(from: page.string ?? "")
            var count = 0
            for i in 0..<lines.count {
                guard isHeaderLine(lines[i]) else { continue }
                var k = i + 1
                var look = 0
                while k < lines.count, look < 3 {
                    let candidate = lines[k]
                    if candidate.isEmpty { k += 1; continue }
                    if isHeaderLine(candidate) { break }
                    if candidate.split(separator: " ").count >= 6 { count += 1; break }
                    k += 1
                    look += 1
                }
            }
            out[pageIndex] = count
        }
        return out
    }

    private static func isHeaderLine(_ line: String) -> Bool {
        if matchHeaderCodeShape(on: line) != nil { return true }
        return line.range(of: CatalogPDFHeaderGrammar.numNumSplitPattern, options: .regularExpression) != nil
    }

    /// Finds the longest contiguous page run with sustained course-code density.
    static func inferCourseDescriptionPageRange(
        document: PDFDocument,
        minimumPerPage: Int = 2,
        programsStartPage: Int? = nil
    ) -> Range<Int>? {
        if let anchored = inferCourseDescriptionRangeFromTextAnchor(
            document: document,
            programsStartPage: programsStartPage
        ) {
            return anchored
        }

        let density = codeDensityByPage(document: document)
        guard !density.isEmpty else { return nil }

        var bestRange: Range<Int>?
        var bestScore = 0
        var runStart: Int?
        var runScore = 0

        for entry in density {
            if entry.count >= minimumPerPage {
                if runStart == nil { runStart = entry.pageIndex }
                runScore += entry.count
            } else if let start = runStart {
                let end = entry.pageIndex
                if runScore > bestScore {
                    bestScore = runScore
                    bestRange = start..<end
                }
                runStart = nil
                runScore = 0
            }
        }

        if let start = runStart {
            let end = density.last!.pageIndex + 1
            if runScore > bestScore {
                bestRange = start..<end
            }
        }

        if let programsStartPage, var range = bestRange {
            range = range.lowerBound..<min(range.upperBound, programsStartPage)
            if range.lowerBound < range.upperBound {
                bestRange = range
            }
        }

        return bestRange
    }

    /// Uses explicit "Courses" / "Course Descriptions" headings to locate the catalog body.
    private static func inferCourseDescriptionRangeFromTextAnchor(
        document: PDFDocument,
        programsStartPage: Int?
    ) -> Range<Int>? {
        let minimumStartPage = 40
        var startPage: Int?

        for pageIndex in minimumStartPage..<document.pageCount {
            let text = document.page(at: pageIndex)?.string ?? ""
            for rawLine in text.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard isCourseSectionHeadingLine(line) else { continue }
                startPage = pageIndex
                break
            }
            if startPage != nil { break }
        }
        guard let startPage else { return nil }

        let density = codeDensityByPage(document: document)
        var endPage = programsStartPage.map { max(startPage, $0 - 1) } ?? (document.pageCount - 1)

        // Extend through trailing low-density pages that still contain occasional course headers.
        var trailingQuiet = 0
        for entry in density where entry.pageIndex >= startPage {
            if entry.pageIndex > endPage { break }
            if entry.count == 0 {
                trailingQuiet += 1
                if trailingQuiet >= 12 {
                    endPage = max(startPage, entry.pageIndex - 12)
                    break
                }
            } else {
                trailingQuiet = 0
                endPage = max(endPage, entry.pageIndex)
            }
        }

        guard startPage <= endPage else { return nil }
        return startPage..<(endPage + 1)
    }

    /// True for real section headings, not TOC lines like `Department of … Courses … 84`.
    private static func isCourseSectionHeadingLine(_ line: String) -> Bool {
        if line.range(of: #"\.{3,}\s*\d+\s*$"#, options: .regularExpression) != nil { return false }
        let patterns = [
            #"^(?:\d+\s+)?Department of .{3,100} Courses\s*$"#,
            #"^(?:\d+\s+)?Course Descriptions\s*$"#,
            #"^(?:\d+\s+)?Programs and Courses of Instruction\s*$"#,
        ]
        return patterns.contains {
            line.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    // MARK: - Header / metadata matching

    private static func matchHeaderCodeShape(on line: String) -> CatalogPDFHeaderCodeShape? {
        for header in CatalogPDFHeaderGrammar.builtins {
            if matchesRegex(header.headerPattern, on: line) {
                return header.codeShape
            }
        }
        if line.range(of: CatalogPDFHeaderGrammar.numNumSplitPattern, options: .regularExpression) != nil {
            return .numNum
        }
        return nil
    }

    private static func detectMetadataGrammar(
        lines: [String],
        headerShape: CatalogPDFHeaderCodeShape,
        headerLineIndices: [Int]
    ) -> CatalogPDFMetadataGrammar {
        var scores: [CatalogPDFMetadataGrammar: Int] = [:]
        let sampleIndices = Array(headerLineIndices.prefix(400))

        for index in sampleIndices {
            let headerLine = lines[index]
            let window = (index...(min(index + 2, lines.count - 1))).map { lines[$0] }
            if metadataPattern(.inlineParenthetical).matchesAny(in: [headerLine] + Array(window.dropFirst())) {
                scores[.inlineParenthetical, default: 0] += 1
            }
            if window.count > 1, window.dropFirst().contains(where: { extractHoursCredits(from: $0) != nil }) {
                scores[.nextLineHoursCredits, default: 0] += 1
            }
            if window.count > 1, metadataPattern(.nextLineTermUnits).matchesAny(in: Array(window.dropFirst())) {
                scores[.nextLineTermUnits, default: 0] += 1
            }
            if extractTrailingUnits(from: headerLine) != nil {
                scores[.trailingUnitsRange, default: 0] += 1
            }
        }

        if headerShape == .alphaNumDot {
            scores[.inlineParenthetical, default: 0] += 2
        }
        if headerShape == .numNum {
            scores[.trailingUnitsRange, default: 0] += 1
            scores[.nextLineTermUnits, default: 0] += 1
        }
        if headerShape == .alphaNum {
            scores[.nextLineHoursCredits, default: 0] += 2
        }

        return scores.max(by: { $0.value < $1.value })?.key ?? defaultMetadata(for: headerShape)
    }

    private static func defaultMetadata(for shape: CatalogPDFHeaderCodeShape) -> CatalogPDFMetadataGrammar {
        switch shape {
        case .alphaNumDot: return .inlineParenthetical
        case .alphaNum: return .nextLineHoursCredits
        case .numNum: return .trailingUnitsRange
        }
    }

    private static func metadataPattern(_ grammar: CatalogPDFMetadataGrammar) -> MetadataPattern {
        switch grammar {
        case .inlineParenthetical:
            return MetadataPattern(
                regex: #"\(\s*(\d+(?:\.\d+)?)(?:\s*(?:to|or|-|–|—)\s*(\d+(?:\.\d+)?))?\s*[Cc]redits?\s*\)"#
            )
        case .nextLineHoursCredits:
            return MetadataPattern(
                regex: #"\b(\d+(?:\.\d+)?)\s+hours?\s*[;,]\s*(\d+(?:\.\d+)?)\s+credits?\b"#
            )
        case .nextLineTermUnits:
            return MetadataPattern(
                regex: #"(?:(?:fall|spring|summer|winter|all\s+semesters|intermittent)[^:\n]*:\s*)?(\d+(?:\.\d+)?)\s+units?\b"#,
                options: [.caseInsensitive]
            )
        case .trailingUnitsRange:
            return MetadataPattern(
                regex: #"\s(\d+(?:-\d+)?)\s*$"#
            )
        }
    }

    private struct MetadataPattern {
        let regex: String
        let options: NSRegularExpression.Options

        init(regex: String, options: NSRegularExpression.Options = []) {
            self.regex = regex
            self.options = options
        }

        func matchesAny(in lines: [String]) -> Bool {
            lines.contains { line in
                guard let compiled = try? NSRegularExpression(pattern: regex, options: options) else { return false }
                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                return compiled.firstMatch(in: line, range: range) != nil
            }
        }

        func firstMatch(in text: String, creditGroupIndex: Int = 1) -> (credits: Int, range: Range<String.Index>)? {
            guard let compiled = try? NSRegularExpression(pattern: regex, options: options) else { return nil }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = compiled.firstMatch(in: text, range: range) else { return nil }

            guard creditGroupIndex < match.numberOfRanges,
                  match.range(at: creditGroupIndex).location != NSNotFound,
                  let valueRange = Range(match.range(at: creditGroupIndex), in: text),
                  let tokenRange = Range(match.range, in: text) else { return nil }

            let credits = Int((Double(text[valueRange]) ?? 0).rounded())
            return (max(0, credits), tokenRange)
        }
    }

    static func extractCredits(from text: String, metadata: CatalogPDFMetadataGrammar) -> Int? {
        switch metadata {
        case .trailingUnitsRange:
            return extractTrailingUnits(from: text)?.credits
        case .nextLineHoursCredits:
            return extractHoursCredits(from: text)
        case .inlineParenthetical:
            return inlineParentheticalCredits(from: text)
        default:
            return metadataPattern(metadata).firstMatch(in: text, creditGroupIndex: 1)?.credits
        }
    }

    /// Extracts the credit value from a `(N Credits)` / `(N to M Credits)` token.
    ///
    /// For ranges (`0 to 4`, `3 or 4`) the upper bound is the representative credit
    /// weight, so we return the max — storing the `0` lower bound of a `0 to 4` course
    /// would mislabel a graded course as zero-credit.
    private static func inlineParentheticalCredits(from text: String) -> Int? {
        let pattern = #"\(\s*(\d+(?:\.\d+)?)(?:\s*(?:to|or|-|–|—)\s*(\d+(?:\.\d+)?))?\s*[Cc]redits?\s*\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let lowRange = Range(match.range(at: 1), in: text) else { return nil }
        var value = Int((Double(text[lowRange]) ?? 0).rounded())
        if match.range(at: 2).location != NSNotFound,
           let highRange = Range(match.range(at: 2), in: text) {
            value = max(value, Int((Double(text[highRange]) ?? 0).rounded()))
        }
        return max(0, value)
    }

    /// Strips a trailing CMU units token (`9`, `9-10`, `12`) from a header title fragment.
    static func extractTrailingUnits(from text: String) -> (title: String, credits: Int)? {
        let pattern = #"^(.*\S)\s+(\d+(?:-\d+)?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              match.numberOfRanges >= 3,
              let titleRange = Range(match.range(at: 1), in: text),
              let unitsRange = Range(match.range(at: 2), in: text) else {
            return nil
        }
        let title = String(text[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let unitsToken = String(text[unitsRange])
        guard !title.isEmpty else { return nil }

        let credits: Int
        if unitsToken.contains("-") {
            guard let first = Int(unitsToken.split(separator: "-").first ?? "") else { return nil }
            credits = first
        } else {
            guard let value = Int(unitsToken), value >= 3, value <= 15 else { return nil }
            if title.lowercased().hasSuffix("course") { return nil }
            credits = value
        }
        return (title, credits)
    }

    /// True when a line opens a Brooklyn-style "N hours … N credits" metadata block.
    ///
    /// Brooklyn entries wrap the credit value onto subsequent lines (e.g. the hours
    /// clause runs long and `3 credits` lands on its own line, or the value and the
    /// word `credits` are split as `…); 3` + `credits`). Detecting the *start* of the
    /// block lets the parser accumulate continuation lines until the credit appears.
    static func lineBeginsHoursCreditsBlock(_ line: String) -> Bool {
        if line.range(of: #"(?i)\b\d+(?:\.\d+)?\s+(?:hours?|credits?)\b"#, options: .regularExpression) != nil {
            return true
        }
        // Spelled-out hours ("Minimum of nine hours … ; 3") still open a block as long as
        // a digit (the wrapped credit value) is present on the line.
        if line.range(of: #"(?i)\b(?:hours?|credits?)\b"#, options: .regularExpression) != nil,
           line.range(of: #"\d"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    /// Extracts the credit value from an accumulated hours/credits metadata buffer.
    ///
    /// Ignores `hours` tokens and returns the first explicit `N credits` value, so a
    /// wrapped or split credit clause still resolves to the correct number.
    static func creditsFromHoursCreditsBuffer(_ buffer: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)(\d+(?:\.\d+)?)\s+credits?\b"#) else { return nil }
        let range = NSRange(buffer.startIndex..<buffer.endIndex, in: buffer)
        guard let match = regex.firstMatch(in: buffer, range: range),
              let valueRange = Range(match.range(at: 1), in: buffer) else { return nil }
        return max(0, Int((Double(buffer[valueRange]) ?? 0).rounded()))
    }

    static func lineLooksLikeMetadata(_ line: String, metadata: CatalogPDFMetadataGrammar) -> Bool {
        switch metadata {
        case .trailingUnitsRange:
            return extractTrailingUnits(from: line) != nil
        case .nextLineHoursCredits:
            return extractHoursCredits(from: line) != nil
        default:
            return metadataPattern(metadata).matchesAny(in: [line])
        }
    }

    private static func extractHoursCredits(from line: String) -> Int? {
        let patterns: [(String, Int)] = [
            (#"\b(\d+(?:\.\d+)?)\s+hours?\s*[;,]\s*(\d+(?:\.\d+)?)\s+credits?\b"#, 2),
            (#"\b(\d+(?:\.\d+)?)\s+credits?\s*[;,]\s*(\d+(?:\.\d+)?)\s+hours?\b"#, 1),
            (#"[;,]\s*(\d+(?:\.\d+)?)\s+credits?\b"#, 1),
        ]
        for (pattern, group) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  group < match.numberOfRanges,
                  let valueRange = Range(match.range(at: group), in: line) else { continue }
            let credits = Int((Double(line[valueRange]) ?? 0).rounded())
            return max(0, credits)
        }
        return nil
    }

    // MARK: - Helpers

    private static func normalizedLines(from text: String) -> [String] {
        text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .components(separatedBy: .newlines)
            .map {
                $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    private static func matchesRegex(_ pattern: String, on line: String) -> Bool {
        line.range(of: pattern, options: .regularExpression) != nil
    }

    private static func preferredCodeShape(from profile: CatalogPDFProfileData?) -> CatalogPDFHeaderCodeShape? {
        guard let profile else { return nil }
        if CatalogPDFProfileLoader.supportsCMUStyleCourseCodes(profile) { return .numNum }
        let patterns = profile.blockRules?.courseCodePatterns ?? profile.courseCodePatterns
        if patterns.contains(where: { $0.contains(#"\."#) }) {
            return .alphaNumDot
        }
        return nil
    }

    private static func rankScores(
        _ scores: [CatalogPDFHeaderCodeShape: Int],
        preferred: CatalogPDFHeaderCodeShape?
    ) -> [(key: CatalogPDFHeaderCodeShape, value: Int)] {
        scores.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            if let preferred {
                if lhs.key == preferred { return true }
                if rhs.key == preferred { return false }
            }
            return lhs.key.rawValue < rhs.key.rawValue
        }
    }

    private static func scoreConfidence(winnerCount: Int, runnerUpCount: Int, sampleSize: Int) -> Double {
        guard winnerCount >= minimumSampleSize else { return sampleSize > 0 ? 0.5 : 0 }
        guard winnerCount > 0 else { return 0 }
        let margin = Double(winnerCount - runnerUpCount) / Double(winnerCount)
        return min(1, max(0, margin))
    }

    private static func fallbackResult(preferredCodeShape: CatalogPDFHeaderCodeShape?) -> CatalogPDFCourseFormatDetectionResult {
        let shape = preferredCodeShape ?? .alphaNumDot
        let grammar = CatalogPDFCourseEntryGrammar(
            header: CatalogPDFHeaderGrammar.builtin(for: shape),
            metadata: defaultMetadata(for: shape)
        )
        return CatalogPDFCourseFormatDetectionResult(
            grammar: grammar,
            confidence: 0,
            sampleSize: 0,
            evidence: [:]
        )
    }
}
