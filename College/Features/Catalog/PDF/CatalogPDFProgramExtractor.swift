// CatalogPDFProgramExtractor.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogPDFProgramExtractor.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Stage 4 recognition: programs from classified blocks only.
enum CatalogPDFProgramExtractor {
    private static let degreeTokenRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?i)\b(AA|AS|AAS|BA|BS|MA|MS|MBA|MENG|MPH|MFA|BFA|BM|JD|MD|PhD|PHD|DMD|DDS|DPT|PHARMD|MSTAT|MPP)\b"#,
        options: []
    )

    private static let minorRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?i)\bminor(s)?\b"#,
        options: []
    )

    private static let programTitleSignalRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?i)\b(major(s)?|minor(s)?|concentration(s)?|bachelor|master|associate|B\.?A\.?|B\.?S\.?|M\.?A\.?|M\.?S\.?|M\.?B\.?A\.?|M\.?S\.?W\.?|Ph\.?D\.?)\b"#,
        options: []
    )

    private static let outlineDegreeRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?i)\b(M\.?A\.?|M\.?S\.?|M\.?B\.?A\.?|M\.?S\.?W\.?|M\.?S\.?E\.?|M\.?S\.?T\.?|Ph\.?D\.?|Ed\.?D\.?|D\.?M\.?A\.?)\b"#,
        options: []
    )

    private static let outlinePageReferenceRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"\s*\(p\.\s*\d+\)\s*$"#,
        options: [.caseInsensitive]
    )

    static func extractFromOutline(
        entries: [CatalogPDFOutlineEntry],
        sourceURL: URL
    ) -> [ScrapedProgram] {
        var programs: [ScrapedProgram] = []
        var seen: Set<String> = []

        for entry in entries {
            guard let candidate = parseOutlineProgram(entry: entry, sourceURL: sourceURL) else { continue }
            let key = "\(candidate.type)|\(candidate.name)".lowercased()
            guard seen.insert(key).inserted else { continue }
            programs.append(candidate)
        }

        programs.sort {
            if $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedSame {
                return $0.type.localizedCaseInsensitiveCompare($1.type) == .orderedAscending
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return programs
    }

    static func extract(
        from classifiedBlocks: [CatalogPDFClassifiedBlock],
        minConfidence: Float
    ) -> (programs: [ScrapedProgram], diagnostics: CatalogPDFBlockClassificationDiagnostics) {
        var programs: [ScrapedProgram] = []
        var seen: Set<String> = []
        var candidates = 0
        var accepted = 0
        var rejected = 0
        var sampleRejections: [String] = []
        var sampleAccepted: [String] = []
        var blocksByType: [String: Int] = [:]
        var acceptedConfidenceTotal: Double = 0

        for block in classifiedBlocks {
            blocksByType[block.type.rawValue, default: 0] += 1
        }

        for classified in classifiedBlocks where classified.type == .program {
            candidates += 1
            guard classified.confidence >= minConfidence else {
                rejected += 1
                if sampleRejections.count < 8 {
                    sampleRejections.append("below_threshold(\(classified.confidence)): \(classified.block.text.prefix(80))")
                }
                continue
            }

            if CatalogPDFProgramRejectLexicon.hasStrongNegative(classified.block.text) {
                rejected += 1
                if sampleRejections.count < 8 {
                    sampleRejections.append("lexicon: \(classified.block.text.prefix(80))")
                }
                continue
            }

            guard let program = parseProgram(from: classified) else {
                rejected += 1
                if sampleRejections.count < 8 {
                    sampleRejections.append("parse_failed: \(classified.block.text.prefix(80))")
                }
                continue
            }

            let key = "\(program.type)|\(program.name)".lowercased()
            guard seen.insert(key).inserted else { continue }

            programs.append(program)
            accepted += 1
            acceptedConfidenceTotal += Double(classified.confidence)
            if sampleAccepted.count < 8 {
                let ev = classified.evidence.matchedRules.joined(separator: ",")
                sampleAccepted.append("\(program.name) conf=\(classified.confidence) [\(ev)]")
            }
        }

        let diagnostics = CatalogPDFBlockClassificationDiagnostics(
            totalBlocks: classifiedBlocks.count,
            blocksByType: Self.sortedBlocksByType(blocksByType),
            programCandidates: candidates,
            programAccepted: accepted,
            programRejected: rejected,
            sampleRejections: sampleRejections,
            sampleAcceptedEvidence: sampleAccepted,
            averageAcceptedProgramConfidence: accepted > 0 ? (acceptedConfidenceTotal / Double(accepted)) : nil
        )

        programs.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        return (programs, diagnostics)
    }

    private static func sortedBlocksByType(_ counts: [String: Int]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: counts.keys.sorted().map { ($0, counts[$0] ?? 0) })
    }

    private static func parseOutlineProgram(entry: CatalogPDFOutlineEntry, sourceURL: URL) -> ScrapedProgram? {
        let title = entry.title
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !isOutlineGroupingOrNoise(title) else { return nil }

        let lower = title.lowercased()
        let programType: String
        var name = title
        var degreeType: String?

        if lower.hasSuffix(" major") || lower.contains(" major (") || lower.hasSuffix(" double major") {
            programType = "Major"
            name = stripProgramSuffixes(from: name, suffixes: ["Double Major", "Major"])
        } else if lower.hasSuffix(" minor") || lower.contains(" minor (") {
            programType = "Minor"
            name = stripProgramSuffixes(from: name, suffixes: ["Minor"])
        } else if containsOutlineDegreeSignal(title) {
            programType = "Graduate Program"
            degreeType = extractOutlineDegreeToken(from: title)
        } else if let parsed = parseOutlineDegreeRegistryTitle(title) {
            programType = parsed.programType
            name = parsed.name
            degreeType = parsed.degreeType
        } else if isNamedProgramOutlineTitle(title) {
            // Catalogs that name degree programs as "<Field> Program" (e.g. CMU's
            // "Computer Science Program", "Robotics Program"). Singular " program"
            // only; grouping headers ("...Programs", "...Program Courses") are
            // excluded by isOutlineGroupingOrNoise / the suffix check.
            programType = "Major"
            name = stripProgramSuffixes(from: name, suffixes: ["Program"])
        } else {
            return nil
        }

        name = cleanOutlineProgramName(name)
        guard name.count >= 3, name.count <= 120 else { return nil }
        guard isPlausibleOutlineProgramName(name) else { return nil }

        var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false)
        if let pageIndex = entry.pageIndex, pageIndex >= 0 {
            components?.fragment = "page=\(pageIndex + 1)"
        }

        return ScrapedProgram(
            name: name,
            type: programType,
            url: components?.url?.absoluteString ?? sourceURL.absoluteString,
            group: nil,
            department: nil,
            college: nil,
            degreeType: degreeType,
            requirements: nil
        )
    }

    private static func stripProgramSuffixes(from title: String, suffixes: [String]) -> String {
        var output = title
        for suffix in suffixes {
            output = output.replacingOccurrences(
                of: #"(?i)\s+\#(suffix)(?=\s*(?:\(|$))"#,
                with: "",
                options: .regularExpression
            )
        }
        return output
    }

    private static func cleanOutlineProgramName(_ title: String) -> String {
        var name = title
            .replacingOccurrences(of: #"^[•\-\s]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let re = outlinePageReferenceRegex {
            let ns = NSRange(name.startIndex..<name.endIndex, in: name)
            name = re.stringByReplacingMatches(in: name, range: ns, withTemplate: "")
        }
        return name
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseOutlineDegreeRegistryTitle(_ title: String) -> (name: String, degreeType: String, programType: String)? {
        let cleaned = cleanOutlineProgramName(title)
        let lower = cleaned.lowercased()
        if lower.hasPrefix("department of ") || lower.hasPrefix("school of ") {
            return nil
        }

        let commaPattern = #",\s*([A-Za-z. ]{2,20})\s*$"#
        if let regex = try? NSRegularExpression(pattern: commaPattern, options: []),
           let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)),
           match.numberOfRanges >= 2,
           let tokenRange = Range(match.range(at: 1), in: cleaned),
           let fullRange = Range(match.range(at: 0), in: cleaned) {
            let suffix = String(cleaned[tokenRange])
            let token = DegreeTokenRegistry.normalizeToken(suffix)
            if DegreeTokenRegistry.isKnownToken(token) {
                let name = String(cleaned[..<fullRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ","))
                guard name.count >= 3 else { return nil }
                let programType = DegreeTokenRegistry.entry(forNormalizedToken: token)?.degreeLevel == DegreeConfiguration.undergraduate
                    ? "Major" : "Graduate Program"
                return (name, token, programType)
            }
        }

        for entry in DegreeTokenRegistry.allEntries {
            let phrase = entry.displayLabel.lowercased()
            let inPrefix = phrase + " in "
            if lower.hasPrefix(inPrefix) {
                let name = String(cleaned.dropFirst(inPrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard name.count >= 3 else { return nil }
                let programType = entry.degreeLevel == DegreeConfiguration.undergraduate ? "Major" : "Graduate Program"
                return (name, entry.token, programType)
            }
        }

        return nil
    }

    private static func containsOutlineDegreeSignal(_ title: String) -> Bool {
        let ns = NSRange(title.startIndex..<title.endIndex, in: title)
        return outlineDegreeRegex?.firstMatch(in: title, range: ns) != nil
    }

    private static func extractOutlineDegreeToken(from title: String) -> String? {
        guard let re = outlineDegreeRegex else { return nil }
        let ns = NSRange(title.startIndex..<title.endIndex, in: title)
        guard let match = re.firstMatch(in: title, range: ns),
              let range = Range(match.range(at: 1), in: title) else {
            return nil
        }
        let token = String(title[range])
            .replacingOccurrences(of: ".", with: "")
            .uppercased()
        return token.isEmpty ? nil : token
    }

    /// True when an outline title names a degree program as "<Field> Program"
    /// (singular). Excludes plural/grouping headers and course-section entries.
    private static func isNamedProgramOutlineTitle(_ title: String) -> Bool {
        let lower = title.lowercased()
        guard lower.hasSuffix(" program") else { return false }
        // "X Program Courses" never reaches here (ends with "courses"), but guard anyway.
        guard !lower.hasSuffix(" courses") else { return false }
        // Academic units, not programs.
        if lower.hasPrefix("department of ")
            || lower.hasPrefix("school of ")
            || lower.hasPrefix("college of ") {
            return false
        }
        let name = stripProgramSuffixes(from: title, suffixes: ["Program"])
        return cleanOutlineProgramName(name).count >= 3
    }

    private static func isOutlineGroupingOrNoise(_ title: String) -> Bool {
        let lower = title.lowercased()
        let fragments = [
            "academic policies",
            "academic procedures",
            "academic program index",
            "academic programs",
            "appendix",
            "consortium programs",
            "course descriptions",
            "curriculum and courses",
            "degree requirements",
            "departments and interdisciplinary programs",
            "dual degree programs",
            "dual-degree programs",
            "full time and half time",
            "general program requirements",
            "handbook",
            "honors program",
            "leadership programs",
            "limits on number",
            "policies and procedures",
            "program areas",
            "program requirements",
            "special academic programs",
            "student academic policies",
        ]
        return fragments.contains { lower.contains($0) }
    }

    private static func isPlausibleOutlineProgramName(_ name: String) -> Bool {
        guard !CatalogPDFProgramRejectLexicon.hasStrongNegative(name) else { return false }
        guard !looksLikeNoiseProgramName(name) else { return false }
        let lower = name.lowercased()
        let fragments = [
            "course title credits",
            "full academic bulletin",
            "program complete",
            "requirements",
        ]
        return !fragments.contains { lower.contains($0) }
    }

    /// Generic guard against structural noise leaking into program names:
    /// concatenated catalog titles with page numbers, four-digit years, and
    /// all-caps section/heading banners. Kept school-agnostic.
    private static func looksLikeNoiseProgramName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        // Four-digit year (e.g. "2025-2026 Catalog") — never part of a program name.
        if trimmed.range(of: #"\b\d{4}\b"#, options: .regularExpression) != nil {
            return true
        }

        // A single run-together token (no internal spaces) far longer than any
        // real program word — e.g. "CarnegieMellonUniversity2025...Catalog".
        if trimmed.split(separator: " ").contains(where: { $0.count > 28 }) {
            return true
        }

        // Academic-unit banners, not programs.
        let lower = trimmed.lowercased()
        if lower.hasPrefix("college of ")
            || lower.hasPrefix("school of ")
            || lower.hasPrefix("department of ") {
            return true
        }

        // All-caps multi-word banners (e.g. "COLLEGE OF FINE ARTS").
        let letters = trimmed.filter { $0.isLetter }
        if !letters.isEmpty,
           letters.allSatisfy({ $0.isUppercase }),
           trimmed.split(separator: " ").count >= 2 {
            return true
        }

        return false
    }

    private static func parseProgram(from classified: CatalogPDFClassifiedBlock) -> ScrapedProgram? {
        let lines = classified.block.text
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let line = lines.first(where: isProgramTitleLine)
            ?? lines.first
            ?? classified.block.text
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !line.isEmpty, line.count <= 200 else { return nil }

        let ns = NSRange(line.startIndex..<line.endIndex, in: line)
        let isMinor = minorRegex?.firstMatch(in: line, range: ns) != nil
        let degreeToken = extractDegreeToken(from: line) ?? ""
        let programType = isMinor ? "Minor" : "Major"

        var name = line
        if !degreeToken.isEmpty {
            name = name.replacingOccurrences(of: degreeToken, with: "", options: [.caseInsensitive])
        }
        name = name
            .replacingOccurrences(of: #"^[•\-\s]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\d{1,4}\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\s*\(p\.\s*\d+\)\s*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?i)\\bminor(s)?\\b", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?i)\\bmajor(s)?\\b", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?i)\\bconcentration(s)?\\b", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?i)\\b(bachelor|master|associate)\\s+of\\s+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "[-–—:.;]+$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard name.count >= 3, name.count <= 120 else { return nil }
        guard isPlausibleProgramName(name) else { return nil }
        guard !CatalogPDFProgramRejectLexicon.hasStrongNegative(name) else { return nil }

        return ScrapedProgram(
            name: name,
            type: programType,
            url: "",
            group: nil,
            department: nil,
            college: nil,
            degreeType: degreeToken.isEmpty ? nil : degreeToken.uppercased(),
            requirements: nil
        )
    }

    private static func isProgramTitleLine(_ line: String) -> Bool {
        guard line.count <= 200 else { return false }
        guard !CatalogPDFProgramRejectLexicon.hasStrongNegative(line) else { return false }
        let ns = NSRange(line.startIndex..<line.endIndex, in: line)
        return programTitleSignalRegex?.firstMatch(in: line, range: ns) != nil
    }

    private static func isPlausibleProgramName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(where: \.isLetter) else { return false }
        guard !trimmed.hasPrefix("&") else { return false }
        guard !trimmed.hasPrefix("("), !trimmed.hasPrefix(","), !trimmed.firstIsDigit else { return false }
        guard trimmed.firstLetterIsUppercase else { return false }
        guard !trimmed.hasSuffix(",") else { return false }
        guard !looksLikeNoiseProgramName(trimmed) else { return false }

        let lower = trimmed.lowercased()
        let fragments = [
            "choose one",
            "fall term",
            "spring term",
            "core courses",
            "elective courses",
            "credit for experiential learning",
            "4-point scale",
            "after completing",
            "also required",
            "automatically becomes",
            "bachelor's degree transcript",
            "consultation with",
            "count toward",
            "course title credits",
            "courses in",
            "courses that",
            "following six courses",
            "following areas",
            "investigation",
            "prerequisite",
            "requires the following",
            "students",
            "such computing",
        ]
        if fragments.contains(where: { lower.contains($0) }) {
            return false
        }

        return true
    }

    private static func extractDegreeToken(from line: String) -> String? {
        guard let re = degreeTokenRegex else { return nil }
        let ns = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let m = re.firstMatch(in: line, range: ns),
              m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: line) else {
            return nil
        }
        return String(line[r])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "PHD", with: "PhD", options: [.caseInsensitive])
    }
}

private extension String {
    var firstIsDigit: Bool {
        first?.isNumber == true
    }

    var firstLetterIsUppercase: Bool {
        guard let letter = first(where: { $0.isLetter }) else { return false }
        return letter.isUppercase
    }
}
