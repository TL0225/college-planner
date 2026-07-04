// CatalogPDFProgramIndexExtractor.swift
// Feature: Catalog
// Purpose: Generic, school-agnostic extraction of programs / degrees / majors /
//          minors from a catalog's structured body-text signals: the program
//          index (dotted-leader lines) and per-department block headings
//          ("Minor in X", "X degree program ..." + HEGIS/SED codes). Each
//          program is linked to its department via the department index.

import Foundation

enum CatalogPDFProgramIndexExtractor {
    // "<Program Name> .......... 267"  (dotted leader + page number)
    private static let dottedLeaderRegex = try? NSRegularExpression(
        pattern: #"^(.{3,90}?)[\.\u2026]{2,}\s*(\d{1,4})\s*$"#
    )
    // Standalone department-block headings.
    private static let minorInRegex = try? NSRegularExpression(
        pattern: #"^Minor in ([A-Za-z].{2,60})$"#,
        options: [.caseInsensitive]
    )
    private static let majorInRegex = try? NSRegularExpression(
        pattern: #"^Major in ([A-Za-z].{2,60})$"#
    )
    // Brooklyn degree-program heading, confirmed by an adjacent HEGIS/SED code line.
    private static let degreeProgramRegex = try? NSRegularExpression(
        pattern: #"(?i)^(B\.?A\.?|B\.?S\.?|B\.?B\.?A\.?|B\.?F\.?A\.?|B\.?M(?:us)?\.?|M\.?A\.?T\.?|M\.?A\.?|M\.?S\.?|M\.?F\.?A\.?|M\.?B\.?A\.?|Ph\.?D\.?|Doctoral|Advanced Certificate)[ ,.].{0,100}(?:degree|programs?|certificate| in )"#
    )
    private static let hegisRegex = try? NSRegularExpression(
        pattern: #"(?i)\b(HEGIS code|SED (?:program )?code)\b"#
    )
    // Brooklyn-grad bulleted degree line: "- M.A., English teacher HEGIS code ...".
    private static let bulletDegreeRegex = try? NSRegularExpression(
        pattern: #"(?i)^[-•]\s*((?:B|M|Ph|Ed|D)\.?[A-Z]?\.?(?:[A-Z]\.?)?),?\s+(.{3,70}?)\s+(?:HEGIS|SED)\b"#
    )

    static func extract(
        from lines: [CatalogPDFLine],
        departmentIndex: CatalogPDFDepartmentIndex,
        sourceURL: URL
    ) -> [ScrapedProgram] {
        var output: [ScrapedProgram] = []
        var seen: Set<String> = []

        func add(_ program: ScrapedProgram?) {
            guard let program else { return }
            // Degree-bearing programs with the same title are distinct catalog
            // offerings (e.g. B.A. Biology and B.S. Biology). Minors/certificates
            // still dedupe naturally because degreeType is nil for those rows.
            let key = "\(program.type)|\(program.degreeType ?? "")|\(program.name.lowercased())"
            guard seen.insert(key).inserted else { return }
            output.append(program)
        }

        let normalized = lines.map {
            (page: $0.pageIndex,
             text: $0.text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines))
        }

        for (i, entry) in normalized.enumerated() {
            let line = entry.text
            guard !line.isEmpty else { continue }
            let dept = departmentIndex.departmentName(forPage: entry.page)

            // 1) Program index (dotted leader).
            if let parsed = parseDottedLeader(line) {
                add(makeProgram(name: parsed.name, kind: parsed.kind, degree: parsed.degree,
                                department: dept, page: parsed.page, sourceURL: sourceURL))
                continue
            }

            // 2) "Minor in X" / "Major in X" headings.
            if let name = firstGroup(minorInRegex, in: line) {
                add(makeProgram(name: completedWrappedName(name, at: i, in: normalized), kind: .minor, degree: nil, department: dept,
                                page: entry.page, sourceURL: sourceURL))
                continue
            }
            if let name = firstGroup(majorInRegex, in: line) {
                add(makeProgram(name: completedWrappedName(name, at: i, in: normalized), kind: .major, degree: nil, department: dept,
                                page: entry.page, sourceURL: sourceURL))
                continue
            }

            // 3) Bulleted degree line with HEGIS/SED on the same line (Brooklyn grad).
            if let groups = groups(bulletDegreeRegex, in: line, count: 2) {
                let degree = normalizeDegreeToken(groups[0])
                let name = groups[1].trimmingCharacters(in: .whitespacesAndNewlines)
                add(makeProgram(name: name, kind: gradLevel(for: degree) ? .graduate : .major,
                                degree: degree, department: dept, page: entry.page, sourceURL: sourceURL))
                continue
            }

            // 4) Degree-program heading confirmed by an adjacent HEGIS/SED code line.
            if line.count <= 110,
               degreeProgramRegex?.firstMatch(in: line, range: nsRange(line)) != nil,
               hasNearbyHEGIS(in: normalized, around: i) {
                let degree = leadingDegreeToken(line)
                let name = cleanDegreeProgramName(line)
                if name.count >= 3 {
                    let kind = inferredDegreeProgramKind(from: line, degree: degree)
                    add(makeProgram(name: name, kind: kind,
                                    degree: degree, department: dept, page: entry.page, sourceURL: sourceURL))
                }
                continue
            }

            // 5) HEGIS/SED-confirmed heading where the code line trails a wrapped
            //    degree/program heading by a few lines. This catches Brooklyn's
            //    undergraduate and graduate bulletin layouts without school-specific
            //    rules.
            if hegisRegex?.firstMatch(in: line, range: nsRange(line)) != nil,
               let heading = nearbyDegreeHeading(in: normalized, around: i) {
                let parsedHeading = parseExplicitDegreeProgramHeading(heading)
                let degree = parsedHeading?.degree ?? leadingDegreeToken(heading)
                let kind = inferredDegreeProgramKind(from: heading, degree: degree)
                let name = parsedHeading?.name ?? cleanDegreeProgramName(heading)
                if name.count >= 3 {
                    add(makeProgram(name: name, kind: kind, degree: degree,
                                    department: dept, page: entry.page, sourceURL: sourceURL))
                }
                continue
            }
        }

        output.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return output
    }

    // MARK: - Kinds

    private enum ProgramKind { case major, minor, concentration, graduate, certificate }

    private static func makeProgram(
        name rawName: String,
        kind: ProgramKind,
        degree: String?,
        department: String?,
        page: Int?,
        sourceURL: URL
    ) -> ScrapedProgram? {
        let name = cleanProgramName(rawName)
        guard name.count >= 3, name.count <= 120 else { return nil }
        guard isPlausibleProgramName(name) else { return nil }

        let type: String
        switch kind {
        case .major: type = "Major"
        case .minor: type = "Minor"
        case .concentration: type = "Concentration"
        case .graduate: type = "Graduate Program"
        case .certificate: type = "Certificate"
        }

        var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false)
        if let page, page >= 0 { components?.fragment = "page=\(page + 1)" }

        return ScrapedProgram(
            name: name,
            type: type,
            url: components?.url?.absoluteString ?? sourceURL.absoluteString,
            group: nil,
            department: department,
            college: nil,
            degreeType: degree,
            requirements: nil
        )
    }

    // MARK: - Dotted-leader parsing

    private static func parseDottedLeader(_ line: String) -> (name: String, kind: ProgramKind, degree: String?, page: Int)? {
        guard let g = groups(dottedLeaderRegex, in: line, count: 2) else { return nil }
        let name = g[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let page = Int(g[1]) ?? -1
        let lower = name.lowercased()

        // Must look like a program, not a policy/TOC heading.
        let kind: ProgramKind
        if lower.hasSuffix(" minor") || lower.contains(" minor (") {
            kind = .minor
        } else if lower.hasSuffix(" major") || lower.contains(" major (") {
            kind = .major
        } else if lower.hasSuffix(" concentration") || lower.contains(" concentration (") {
            kind = .concentration
        } else if lower.contains("certificate") {
            kind = .certificate
        } else if containsGraduateSignal(name) {
            kind = .graduate
        } else {
            return nil
        }
        return (name, kind, kind == .graduate ? gradDegreeToken(name) : nil, page)
    }

    // MARK: - Helpers

    private static func cleanProgramName(_ raw: String) -> String {
        var name = raw
            .replacingOccurrences(of: #"^[•\-\s]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*\(p\.\s*\d+\)\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip trailing type words so the bare field name remains.
        for suffix in ["Double Major", "Major", "Minor", "Concentration"] {
            let pattern = "(?i)\\s+" + suffix + "(?=\\s*(?:\\(|$))"
            name = name.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        // "Minor in X" / "Major in X" already stripped at call sites; strip leading degree prose.
        name = name
            .replacingOccurrences(of: #"(?i)^the\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^(bachelor|master|associate) of [a-z ]+ in\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^(B\.?A\.?|B\.?S\.?|M\.?A\.?|M\.?S\.?|Ph\.?D\.?)\s+in\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[-–—:.;,]+$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name
    }

    private static let singleWordSubjectNoise: Set<String> = [
        "english", "french", "spanish", "history", "music", "economics", "biology", "chemistry",
        "physics", "mathematics", "math", "philosophy", "psychology", "sociology", "anthropology",
        "accounting", "finance", "marketing", "management", "theater", "theatre", "art", "dance"
    ]

    private static func isPlausibleProgramName(_ name: String) -> Bool {
        guard name.contains(where: \.isLetter) else { return false }
        guard name.first?.isLetter == true || name.first?.isNumber == false else { return false }
        let lower = name.lowercased()
        let noise = ["academic program index", "table of contents", "index", "requirements",
                     "see ", "following", "the college", "students must", "allows an additional", "p. "]
        if noise.contains(where: { lower.contains($0) }) { return false }
        if name.range(of: #"[.!?]"#, options: .regularExpression) != nil { return false }
        // Truncated headings that wrap mid-phrase (common in CMU minor lists).
        let dangling = [" and", " or", " in", " of", " for", " with", " to", " the"]
        if dangling.contains(where: { lower.hasSuffix($0) }) { return false }
        if CatalogPDFProgramRejectLexicon.hasStrongNegative(name) { return false }
        // Wrapped degree headings sometimes collapse to a lone subject word ("English").
        if !name.contains(" "),
           name.count <= 14,
           singleWordSubjectNoise.contains(lower) {
            return false
        }
        return true
    }

    private static func inferredDegreeProgramKind(from heading: String, degree: String?) -> ProgramKind {
        if heading.range(of: #"(?i)\bcertificate\b"#, options: .regularExpression) != nil {
            return .certificate
        }
        if heading.range(of: #"(?i)\bdoctoral\b"#, options: .regularExpression) != nil {
            return .graduate
        }
        return gradLevel(for: degree) ? .graduate : .major
    }

    private static func completedWrappedName(
        _ name: String,
        at index: Int,
        in lines: [(page: Int, text: String)]
    ) -> String {
        let lower = name.lowercased()
        let dangling = [" and", " or", " in", " of", " for", " with", " to", " the"]
        guard dangling.contains(where: { lower.hasSuffix($0) }),
              index + 1 < lines.count else {
            return name
        }
        let next = lines[index + 1].text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard next.count <= 60,
              next.range(of: #"^[A-Z][A-Za-z0-9 ,&'/().-]{1,60}$"#, options: .regularExpression) != nil,
              CatalogPDFDepartmentExtractor.recognizeDepartmentName(next) == nil else {
            return name
        }
        return "\(name) \(next)"
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsGraduateSignal(_ s: String) -> Bool {
        s.range(of: #"(?i)\b(master of|master's|M\.?A\.?|M\.?S\.?|M\.?B\.?A\.?|M\.?F\.?A\.?|M\.?S\.?W\.?|Ph\.?D\.?|Ed\.?D\.?|D\.?M\.?A\.?|doctor of|doctoral)\b"#,
                options: .regularExpression) != nil
    }

    private static func gradDegreeToken(_ s: String) -> String? { gradDegreeMatch(s) }
    private static func leadingDegreeToken(_ s: String) -> String? { gradDegreeMatch(s) ?? ugDegreeMatch(s) }

    private static func gradDegreeMatch(_ s: String) -> String? {
        match(#"(?i)\b(M\.?A\.?T\.?|M\.?A\.?|M\.?S\.?|M\.?B\.?A\.?|M\.?F\.?A\.?|M\.?S\.?W\.?|Ph\.?D\.?|Ed\.?D\.?|D\.?M\.?A\.?)\b"#, in: s)
            .map { normalizeDegreeToken($0) }
    }
    private static func ugDegreeMatch(_ s: String) -> String? {
        match(#"(?i)\b(B\.?A\.?|B\.?S\.?|B\.?B\.?A\.?|B\.?F\.?A\.?|B\.?M(?:us)?\.?)\b"#, in: s)
            .map { normalizeDegreeToken($0) }
    }

    private static func gradLevel(for degree: String?) -> Bool {
        guard let degree else { return false }
        return degree.hasPrefix("M") || degree.hasPrefix("PH") || degree.hasPrefix("ED") || degree.hasPrefix("D")
    }

    private static func normalizeDegreeToken(_ raw: String) -> String {
        let t = raw.replacingOccurrences(of: ".", with: "").uppercased().trimmingCharacters(in: .whitespaces)
        return t == "PHD" ? "PhD" : t
    }

    private static func cleanDegreeProgramName(_ line: String) -> String {
        var s = line
            .replacingOccurrences(of: #"(?i)\s*HEGIS.*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^(B\.?A\.?|B\.?S\.?|B\.?B\.?A\.?|B\.?F\.?A\.?|B\.?M(?:us)?\.?|M\.?A\.?T\.?|M\.?A\.?|M\.?S\.?|M\.?F\.?A\.?|M\.?B\.?A\.?|Ph\.?D\.?|Doctoral|Advanced Certificate)[ ,.]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\b(?:in Education )?degree program\s*(?::|for|in)?\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bdegree programs\s*(?::|for|in)?\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bcertificate (?:program )?(?:in)?\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\b(degree|program)\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-"))
        if let first = s.first, first.isLowercase { s = first.uppercased() + s.dropFirst() }
        return s
    }

    private static func parseExplicitDegreeProgramHeading(_ heading: String) -> (degree: String, name: String)? {
        let pattern = #"(?i)^(B\.?A\.?|B\.?S\.?|B\.?B\.?A\.?|B\.?F\.?A\.?|B\.?M(?:us)?\.?|M\.?A\.?T\.?|M\.?A\.?|M\.?S\.?|M\.?F\.?A\.?|M\.?B\.?A\.?|Ph\.?D\.?)\s+(?:in Education\s+)?degree programs?\s*(?:in|for|:)?\s+(.{2,90})$"#
        guard let groups = groups(try? NSRegularExpression(pattern: pattern), in: heading, count: 2) else {
            return nil
        }
        return (normalizeDegreeToken(groups[0]), groups[1])
    }

    private static func hasNearbyHEGIS(in lines: [(page: Int, text: String)], around index: Int) -> Bool {
        guard let hegisRegex else { return false }
        let lower = max(0, index)
        let upper = min(lines.count - 1, index + 2)
        for k in lower...upper {
            if hegisRegex.firstMatch(in: lines[k].text, range: nsRange(lines[k].text)) != nil { return true }
        }
        return false
    }

    private static func nearbyDegreeHeading(in lines: [(page: Int, text: String)], around index: Int) -> String? {
        guard let degreeProgramRegex else { return nil }
        let lower = max(0, index - 3)
        for k in stride(from: index, through: lower, by: -1) {
            let text = lines[k].text
            guard text.count <= 110 else { continue }
            if parseExplicitDegreeProgramHeading(text) != nil {
                return completedWrappedDegreeHeading(text, at: k, in: lines)
            }
            if degreeProgramRegex.firstMatch(in: text, range: nsRange(text)) != nil {
                return completedWrappedDegreeHeading(text, at: k, in: lines)
            }
        }
        return nil
    }

    private static func completedWrappedDegreeHeading(
        _ heading: String,
        at index: Int,
        in lines: [(page: Int, text: String)]
    ) -> String {
        guard heading.range(of: #"(?i)(/|-|,|\(|\bfor\b|\bin\b|\band\b|\bof\b)$"#, options: .regularExpression) != nil,
              index + 1 < lines.count else {
            return heading
        }
        let next = lines[index + 1].text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard next.count <= 70,
              next.range(of: #"(?i)\b(HEGIS|SED|Department office|Phone)\b"#, options: .regularExpression) == nil else {
            return heading
        }
        return "\(heading) \(next)"
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Regex utilities

    private static func nsRange(_ s: String) -> NSRange { NSRange(s.startIndex..<s.endIndex, in: s) }

    private static func firstGroup(_ regex: NSRegularExpression?, in line: String) -> String? {
        groups(regex, in: line, count: 1)?.first
    }

    private static func groups(_ regex: NSRegularExpression?, in line: String, count: Int) -> [String]? {
        guard let regex else { return nil }
        guard let match = regex.firstMatch(in: line, range: nsRange(line)), match.numberOfRanges > count else { return nil }
        var out: [String] = []
        for i in 1...count {
            guard let r = Range(match.range(at: i), in: line) else { return nil }
            out.append(String(line[r]).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return out
    }

    private static func match(_ pattern: String, in s: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        guard let m = regex.firstMatch(in: s, range: nsRange(s)), m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r])
    }
}
