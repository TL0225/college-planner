// CatalogPDFRequirementExtractor.swift
// Feature: Catalog
// Purpose: Parse degree-requirement course tables from catalog PDF program sections.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Extracts degree-requirement groups (course lists under category headings) from the
/// program / curriculum sections of a catalog PDF.
///
/// Requirement tables in these catalogs are emitted as rows of `SUBJ 1234 Title <credits>`
/// grouped under a category heading (e.g. "Major Requirements", "Select one of the following").
/// We walk the section text in document order, tracking the current program and category, and
/// only attribute a group to a program when that program name is one we already recognize
/// (from the program extractor). Unattributable groups are dropped rather than guessed.
enum CatalogPDFRequirementExtractor {
    // Row with trailing credits on the same line: "ANTH 3721 The Currency of Historical Memory 4"
    private static let rowWithCreditsRegex = try? NSRegularExpression(
        pattern: #"^([A-Z]{2,6})\s+(\d{3,4}[A-Z]?)\s+(.+?)\s+(\d+(?:\.\d+)?)$"#
    )
    // Row without trailing credits (title may wrap to the next physical line).
    private static let rowNoCreditsRegex = try? NSRegularExpression(
        pattern: #"^([A-Z]{2,6})\s+(\d{3,4}[A-Z]?)\s+(\D.*)$"#
    )

    /// Anchored category headings: a real requirement category starts with one of these
    /// structural words. Matching anywhere in a line (the old behavior) turned ordinary prose
    /// and wrapped course titles into bogus categories, so detection is now prefix-anchored.
    private static let categoryHeadingRegex = try? NSRegularExpression(
        pattern: #"(?i)^(major requirements|minor requirements|core requirements|core curriculum|required courses?|requirements|electives?|elective courses?|concentration|track|tracks|foundation(s)?|foundational courses?|capstone|cognate|distribution|general education|select (one|two|three|four|[0-9]+|from|the following)|choose (one|two|three|four|[0-9]+|from|the following))\b"#
    )

    /// Lines that are table column headers, not categories.
    private static let tableHeaderPhrases: Set<String> = ["course title credits", "code title credits", "course title cr"]

    private static let selectCountRegex = try? NSRegularExpression(
        pattern: #"(?i)\b(select|choose)\s+(one|two|three|four|five|six|seven|eight|nine|ten|\d+)\b"#
    )

    /// A single requirement category with more rows than this is almost certainly merging
    /// unrelated tables across pages (stale program attribution). Such groups are dropped and
    /// attribution is reset rather than emitting wrong data.
    private static let maxCoursesPerGroup = 60
    /// Sanity ceiling on summed credits for one category.
    private static let maxCreditsPerGroup = 150

    /// Legacy entry point retained for callers that only have program rows; returns no rows.
    static func extractRequirements(from programs: [ScrapedProgram]) -> [DegreeRequirement] {
        _ = programs
        return []
    }

    static func extractRequirements(
        from programs: [ScrapedProgram],
        classifiedBlocks: [CatalogPDFClassifiedBlock],
        courseCatalog: [CatalogCourse]
    ) -> [DegreeRequirement] {
        let sectionText = classifiedBlocks
            .filter { $0.sectionKind == .programs || $0.sectionKind == .degreeRequirements }
            .sorted { $0.block.primaryPage < $1.block.primaryPage }
            .map { $0.block.text }
            .joined(separator: "\n")
        return extractRequirements(sectionText: sectionText, knownPrograms: programs, courseCatalog: courseCatalog)
    }

    /// Primary pipeline entry point. Combines two complementary strategies so that
    /// every catalog layout is covered:
    ///   * Strategy A (table): course tables under category headings in the
    ///     classified program / requirement blocks (Fordham-style `SUBJ 1234 …`).
    ///   * Strategy B (anchored): program-heading-anchored walk over document-order
    ///     lines that captures CMU `##-###` unit tables and Brooklyn prose
    ///     requirement blocks (preserved verbatim) and links them to the program
    ///     whose heading precedes them.
    /// Results are merged so each (program, category) is emitted once, preferring
    /// the richer (more course-bearing) group.
    static func extractRequirements(
        from programs: [ScrapedProgram],
        classifiedBlocks: [CatalogPDFClassifiedBlock],
        courseCatalog: [CatalogCourse],
        lines: [CatalogPDFLine],
        subjectNameToCode: [String: String]
    ) -> [DegreeRequirement] {
        let tableRequirements = extractRequirements(
            from: programs,
            classifiedBlocks: classifiedBlocks,
            courseCatalog: courseCatalog
        )
        guard !lines.isEmpty else { return tableRequirements }
        let anchoredRequirements = extractAnchoredRequirements(
            lines: lines,
            knownPrograms: programs,
            courseCatalog: courseCatalog,
            subjectNameToCode: subjectNameToCode
        )
        let merged = mergeRequirements(table: tableRequirements, anchored: anchoredRequirements)
        return reconcileRequirementMajors(merged, programs: programs)
    }

    /// Merges table + anchored groups. The richer source (by group count) is primary;
    /// the other source only contributes keys the primary did not already emit.
    private static func mergeRequirements(
        table: [DegreeRequirement],
        anchored: [DegreeRequirement]
    ) -> [DegreeRequirement] {
        func categoryKey(_ r: DegreeRequirement) -> String {
            "\(normalize(r.major))|\(normalize(r.category))"
        }

        let primary = anchored.count >= table.count ? anchored : table
        let secondary = anchored.count >= table.count ? table : anchored
        var keys = Set(primary.map(categoryKey))
        var result = primary
        for req in secondary where keys.insert(categoryKey(req)).inserted {
            result.append(req)
        }
        return result
    }

    private static func reconcileRequirementMajors(
        _ requirements: [DegreeRequirement],
        programs: [ScrapedProgram]
    ) -> [DegreeRequirement] {
        guard !requirements.isEmpty else { return requirements }
        let lookup = buildProgramLookup(programs)
        return requirements.map { req in
            guard let canon = canonicalProgramName(for: req.major, lookup: lookup, programs: programs) else {
                return req
            }
            guard canon != req.major else { return req }
            return DegreeRequirement(
                id: req.id,
                degreeType: req.degreeType,
                major: canon,
                category: req.category,
                requiredCourses: req.requiredCourses,
                requiredCoursesDetailed: req.requiredCoursesDetailed,
                creditsRequired: req.creditsRequired,
                description: req.description,
                selectFrom: req.selectFrom,
                selectFromDetailed: req.selectFromDetailed,
                selectCount: req.selectCount,
                requirementPredicate: req.requirementPredicate,
                requirementKind: req.requirementKind,
                parentCategory: req.parentCategory,
                displayTitle: req.displayTitle
            )
        }
    }

    private static func canonicalProgramName(
        for rawMajor: String,
        lookup: [String: ProgramRef],
        programs: [ScrapedProgram]
    ) -> String? {
        bestProgramMatch(for: rawMajor, lookup: lookup, programs: programs)?.name
    }

    static func extractRequirements(
        sectionText: String,
        knownPrograms: [ScrapedProgram],
        courseCatalog: [CatalogCourse]
    ) -> [DegreeRequirement] {
        guard !sectionText.isEmpty else { return [] }

        let programLookup = buildProgramLookup(knownPrograms)
        let titleByCode = Dictionary(
            courseCatalog.map { ($0.courseCode, $0.title) },
            uniquingKeysWith: { first, _ in first }
        )

        var requirements: [DegreeRequirement] = []
        var current = Group()

        func flush() {
            if let finished = current.finish(titleByCode: titleByCode) {
                requirements.append(finished)
            }
            current.resetCourses()
        }

        let lines = sectionText.components(separatedBy: .newlines)
        for rawLine in lines {
            let line = rawLine
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if tableHeaderPhrases.contains(normalize(line)) { continue }

            if let row = parseCourseRow(line) {
                current.courses.append(row)
                // Overflow: a category this large is merging unrelated tables. Drop it and stop
                // attributing to this (now stale) program until the next recognized program heading.
                if current.courses.count > maxCoursesPerGroup {
                    current.resetCourses()
                    current.program = nil
                    current.category = nil
                }
                continue
            }

            // A lone integer is a wrapped credit value for the previous row.
            if let credits = Int(line), let last = current.courses.indices.last, current.courses[last].credits == nil {
                current.courses[last].credits = credits
                continue
            }

            if let program = resolveProgram(line: line, lookup: programLookup) {
                flush()
                current.program = program.name
                current.degreeType = program.degreeType
                current.category = nil
                continue
            }

            if isCategoryHeading(line) {
                flush()
                current.category = line
            }
        }
        flush()

        return requirements
    }

    // MARK: - Group accumulation

    private struct ParsedRow {
        let code: String
        var title: String?
        var credits: Int?
    }

    private struct Group {
        var program: String?
        var degreeType: String?
        var category: String?
        var courses: [ParsedRow] = []

        mutating func resetCourses() { courses = [] }

        /// Materializes the current group into a `DegreeRequirement` when it is attributable.
        func finish(
            titleByCode: [String: String]
        ) -> DegreeRequirement? {
            guard let program, !courses.isEmpty, courses.count <= maxCoursesPerGroup else { return nil }
            let detailed: [CourseDetail] = courses.map { row in
                let resolvedTitle = row.title?.isEmpty == false ? row.title : titleByCode[row.code]
                let creditString = row.credits.map(String.init)
                return CourseDetail(code: row.code, title: resolvedTitle, credits: creditString)
            }
            let category = (self.category?.isEmpty == false ? self.category! : "Requirements")
            let selectCount = CatalogPDFRequirementExtractor.selectCount(from: category)
            let isSelective = selectCount != nil
            let creditsRequired = isSelective
                ? CatalogPDFRequirementExtractor.selectedCreditTarget(courses: courses, selectCount: selectCount ?? 1)
                : courses.compactMap { $0.credits }.reduce(0, +)
            guard creditsRequired <= maxCreditsPerGroup else { return nil }
            return DegreeRequirement(
                degreeType: degreeType ?? "",
                major: program,
                category: category,
                requiredCourses: isSelective ? nil : detailed.map(\.code),
                requiredCoursesDetailed: isSelective ? nil : detailed,
                creditsRequired: creditsRequired,
                description: nil,
                selectFrom: isSelective ? detailed.map(\.code) : nil,
                selectFromDetailed: isSelective ? detailed : nil,
                selectCount: selectCount,
                requirementPredicate: isSelective
                    ? .any(detailed.map { .course($0) }, selectCount: selectCount)
                    : .all(detailed.map { .course($0) }),
                requirementKind: isSelective ? .chooseOne : .courseList,
                displayTitle: category
            )
        }
    }

    private struct ProgramRef {
        let name: String
        let degreeType: String?
        let isMinor: Bool
    }

    // MARK: - Parsing helpers

    private static func parseCourseRow(_ line: String) -> ParsedRow? {
        if let regex = rowWithCreditsRegex {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let m = regex.firstMatch(in: line, range: range), m.numberOfRanges >= 5,
               let subjR = Range(m.range(at: 1), in: line),
               let numR = Range(m.range(at: 2), in: line),
               let titleR = Range(m.range(at: 3), in: line),
               let credR = Range(m.range(at: 4), in: line) {
                let code = "\(line[subjR]) \(line[numR])".uppercased()
                let title = String(line[titleR]).trimmingCharacters(in: .whitespaces)
                let credits = Int((Double(line[credR]) ?? 0).rounded())
                return ParsedRow(code: code, title: title.isEmpty ? nil : title, credits: credits)
            }
        }
        if let regex = rowNoCreditsRegex {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let m = regex.firstMatch(in: line, range: range), m.numberOfRanges >= 4,
               let subjR = Range(m.range(at: 1), in: line),
               let numR = Range(m.range(at: 2), in: line),
               let titleR = Range(m.range(at: 3), in: line) {
                let code = "\(line[subjR]) \(line[numR])".uppercased()
                let title = String(line[titleR]).trimmingCharacters(in: .whitespaces)
                return ParsedRow(code: code, title: title.isEmpty ? nil : title, credits: nil)
            }
        }
        return nil
    }

    private static func isCategoryHeading(_ line: String) -> Bool {
        guard line.count <= 160 else { return false }
        guard let first = line.first, first.isUppercase else { return false }
        // Reject lines that end with a digit (wrapped course rows like "... 1945-Pres 4").
        if line.last?.isNumber == true { return false }
        guard let regex = categoryHeadingRegex else { return false }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex.firstMatch(in: line, range: range) != nil
    }

    private static func selectCount(from heading: String) -> Int? {
        guard let regex = selectCountRegex else { return nil }
        let range = NSRange(heading.startIndex..<heading.endIndex, in: heading)
        guard let match = regex.firstMatch(in: heading, range: range),
              match.numberOfRanges >= 3,
              let countRange = Range(match.range(at: 2), in: heading) else { return nil }
        return numberWordValue(String(heading[countRange]))
    }

    private static func numberWordValue(_ token: String) -> Int? {
        if let intValue = Int(token), intValue > 0 { return intValue }
        switch token.lowercased() {
        case "one": return 1
        case "two": return 2
        case "three": return 3
        case "four": return 4
        case "five": return 5
        case "six": return 6
        case "seven": return 7
        case "eight": return 8
        case "nine": return 9
        case "ten": return 10
        default: return nil
        }
    }

    private static func selectedCreditTarget(courses: [ParsedRow], selectCount: Int) -> Int {
        let credits = courses.compactMap(\.credits).filter { $0 > 0 }.sorted(by: >)
        guard !credits.isEmpty else { return 0 }
        return credits.prefix(max(1, selectCount)).reduce(0, +)
    }

    private static func resolveProgram(line: String, lookup: [String: ProgramRef]) -> ProgramRef? {
        guard line.count <= 120 else { return nil }
        return bestProgramMatch(for: line, lookup: lookup, programs: nil, minimumScore: 1.0)
            ?? bestProgramMatch(for: line, lookup: lookup, programs: nil, minimumScore: 0.72)
    }

    private static func buildProgramLookup(_ programs: [ScrapedProgram]) -> [String: ProgramRef] {
        var lookup: [String: ProgramRef] = [:]
        for program in programs {
            let ref = ProgramRef(
                name: program.name,
                degreeType: program.degreeType,
                isMinor: program.type == "Minor"
            )
            registerProgramAlias(program.name, ref: ref, in: &lookup)
            for alias in programAliasKeys(program.name) {
                registerProgramAlias(alias, ref: ref, in: &lookup)
            }
        }
        return lookup
    }

    private static func programAliasKeys(_ name: String) -> [String] {
        var variants: [String] = []
        let noParen = name
            .replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !noParen.isEmpty { variants.append(noParen) }
        if name.contains("-") {
            let parts = name.split(separator: "-", maxSplits: 1)
            if parts.count == 2 {
                let head = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                let tail = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !head.isEmpty { variants.append(head) }
                if !tail.isEmpty { variants.append(tail) }
            }
        }
        let noProgramSuffix = name
            .replacingOccurrences(of: #"(?i)\s+(?:degree\s+)?program$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !noProgramSuffix.isEmpty { variants.append(noProgramSuffix) }
        let noAccelerated = name
            .replacingOccurrences(of: #"(?i)^accelerated\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !noAccelerated.isEmpty, noAccelerated != name { variants.append(noAccelerated) }
        let noEducationPrefix = name
            .replacingOccurrences(of: #"(?i)^education:\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !noEducationPrefix.isEmpty, noEducationPrefix != name { variants.append(noEducationPrefix) }
        let noGradeSuffix = name
            .replacingOccurrences(of: #"(?i)\s*\((?:all\s+grades|grades?\s+[^)]*|\d+\s*-\s*\d+)\)\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !noGradeSuffix.isEmpty, noGradeSuffix != name { variants.append(noGradeSuffix) }
        if let degreeStripped = stripLeadingDegreeToken(from: name) {
            variants.append(degreeStripped)
        }
        if let trailingStripped = stripTrailingDegreeParens(from: name) {
            variants.append(trailingStripped)
        }
        if let wrappedTail = wrappedInPhraseTail(from: name) {
            variants.append(wrappedTail)
        }
        return variants
    }

    /// "(AuD) in audiology" → "audiology" for lookup against fuller program titles.
    private static func wrappedInPhraseTail(from name: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)^\([^)]+\)\s+in\s+(.+)$"#) else { return nil }
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        guard let match = regex.firstMatch(in: name, range: range), match.numberOfRanges >= 2,
              let tailRange = Range(match.range(at: 1), in: name) else { return nil }
        let tail = String(name[tailRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return tail.isEmpty ? nil : tail
    }

    private static func stripTrailingDegreeParens(from name: String) -> String? {
        let stripped = name
            .replacingOccurrences(
                of: #"(?i)\s*\((?:transitional\s+)?[^)]*(?:ph\.?d\.?|m\.?s\.?|m\.?a\.?|m\.?s\.?e\.?|m\.?s\.?t\.?|m\.?b\.?a\.?|m\.?s\.?w\.?|ed\.?d\.?|aud\.?)[^)]*\)\s*$"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty || stripped == name ? nil : stripped
    }

    private static func registerProgramAlias(
        _ rawName: String,
        ref: ProgramRef,
        in lookup: inout [String: ProgramRef]
    ) {
        let key = normalize(rawName)
        guard key.count >= 3 else { return }
        if lookup[key] == nil { lookup[key] = ref }
        let hegisStripped = rawName
            .replacingOccurrences(of: #"(?i)\s*HEGIS.*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,:;-"))
        let hegisKey = normalize(hegisStripped)
        if hegisKey.count >= 3, lookup[hegisKey] == nil { lookup[hegisKey] = ref }
    }

    private static func stripLeadingDegreeToken(from name: String) -> String? {
        let stripped = name
            .replacingOccurrences(
                of: #"(?i)^(B\.?A\.?|B\.?S\.?|B\.?B\.?A\.?|B\.?F\.?A\.?|B\.?M(?:us)?\.?|M\.?A\.?T\.?|M\.?A\.?|M\.?S\.?|M\.?F\.?A\.?|M\.?B\.?A\.?|Ph\.?D\.?|Ed\.?D\.?|D\.?M\.?A\.?|Doctoral|Advanced Certificate)\s*(?:in|of)?\s*"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,:;-"))
        return stripped.isEmpty || stripped == name ? nil : stripped
    }

    private static func normalize(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static let matchStopWords: Set<String> = [
        "in", "of", "the", "and", "for", "a", "an", "degree", "program", "track", "with", "without", "credits"
    ]

    private static func matchTokens(_ value: String) -> Set<String> {
        Set(
            normalize(value)
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count >= 2 && !matchStopWords.contains($0) }
        )
    }

    private static func tokenOverlapScore(_ lhs: String, _ rhs: String) -> Double {
        let left = matchTokens(lhs)
        let right = matchTokens(rhs)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let intersection = left.intersection(right).count
        return Double(intersection) / Double(min(left.count, right.count))
    }

    private static func matchScore(query: String, candidate: String) -> Double {
        let key = normalize(query)
        let candidateKey = normalize(candidate)
        guard key.count >= 3, candidateKey.count >= 3 else { return 0 }
        if key == candidateKey { return 1.0 }
        guard key.count >= 4 || candidateKey.count >= 4 else { return 0 }
        if candidateKey.hasPrefix(key) || key.hasPrefix(candidateKey) { return 0.92 }
        if candidateKey.hasSuffix(key) || key.hasSuffix(candidateKey) { return 0.9 }
        let overlap = tokenOverlapScore(key, candidateKey)
        return overlap >= 0.55 ? overlap : 0
    }

    private static func bestProgramMatch(
        for rawName: String,
        lookup: [String: ProgramRef],
        programs: [ScrapedProgram]?,
        minimumScore: Double = 0.72
    ) -> ProgramRef? {
        let cleaned = rawName
            .replacingOccurrences(of: #"(?i)\bHEGIS.*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,:;-"))
        guard !cleaned.isEmpty else { return nil }

        var best: (ref: ProgramRef, score: Double)?
        func consider(_ candidate: String, ref: ProgramRef) {
            let score = matchScore(query: cleaned, candidate: candidate)
            guard score >= minimumScore else { return }
            if let current = best {
                if score > current.score { best = (ref, score) }
            } else {
                best = (ref, score)
            }
        }

        if let ref = lookup[normalize(cleaned)] { return ref }
        for (alias, ref) in lookup {
            consider(alias, ref: ref)
        }
        if let programs {
            for program in programs {
                consider(program.name, ref: ProgramRef(
                    name: program.name,
                    degreeType: program.degreeType,
                    isMinor: program.type == "Minor"
                ))
            }
        }
        return best?.ref
    }

    // MARK: - Strategy B: program-heading-anchored extraction

    // Unified requirement-section header. Matches the three forms catalogs use:
    //   * parenthetical: "Department requirements (74-84 credits)"
    //   * colon:         "Program Requirements: 18-19 credits"
    //   * bare:          "Department Requirements"
    // An allow-listed prefix word (or none) precedes "requirements" so prose like
    // "admission requirements" / "Requirements Office, 0710 James Hall" is rejected.
    private static let reqHeaderPrefixRegex = try? NSRegularExpression(
        pattern: #"(?i)^((?:(?:department|program|degree|major|minor|concentration|core|core curriculum|general education|advanced certificate|certificate|specialization|honors)\s+)?requirements?)\b\s*(?:\(\s*(\d{1,3})|:|$)"#
    )
    private static let creditsAnywhereRegex = try? NSRegularExpression(
        pattern: #"(?i)\b(\d{1,3})\s*(?:-\s*\d{1,3}\s*)?(?:credits?|units?)\b"#
    )
    // Lines that look like a header by keyword but are actually admissions / office prose.
    private static let reqHeaderRejectRegex = try? NSRegularExpression(
        pattern: #"(?i)\b(admission|matriculation|proficiency|english language|office|deadline|prerequisite)\b"#
    )
    // "Requirements for an interdisciplinary minor in consumer behavior".
    private static let reqHeaderForRegex = try? NSRegularExpression(
        pattern: #"(?i)^(requirements?\s+for\b.{0,60}?\b(?:minor|major|degree|certificate|concentration|program|specialization))\b"#
    )
    private static let runningHeaderRejectRegex = try? NSRegularExpression(
        pattern: #"(?i)\b(catalog|bulletin|page\s+\d+|academic\s+calendar|table\s+of\s+contents)\b"#
    )
    // "A program of 13-16 credits as follows:" — credit-anchored minor opener.
    private static let programOfCreditsRegex = try? NSRegularExpression(
        pattern: #"(?i)^(a program of\s+\d{1,3}(?:\s*-\s*\d{1,3})?\s*(?:credits?|units?)\b.*)$"#
    )
    private static let studentsMustCompleteRegex = try? NSRegularExpression(
        pattern: #"(?i)^students must complete\b"#
    )
    // CMU unit block: "Departmental Core Requirement (1 courses, 9 units):"
    private static let cmuBlockRegex = try? NSRegularExpression(
        pattern: #"(?i)^(.{2,70}?)\(\s*(\d+)\s+courses?,\s*(\d+)\s*units?\)\s*:?\s*$"#
    )
    // CMU row: "76-260 Introduction to Writing Fiction 9".
    private static let cmuRowWithUnitsRegex = try? NSRegularExpression(
        pattern: #"^(\d{2}-\d{3}[A-Z]?)\s+(.+?)\s+(\d+(?:\.\d+)?)$"#
    )
    private static let cmuRowNoUnitsRegex = try? NSRegularExpression(
        pattern: #"^(\d{2}-\d{3}[A-Z]?)\s+(\D.*)$"#
    )
    // Bulleted coded course (Brooklyn grad): "- CASD 7317X/CBSE 7685T: Introduction…".
    private static let bulletCodeRegex = try? NSRegularExpression(
        pattern: #"^[-•]\s*([A-Z]{2,6})\s*(\d{3,4}[A-Z]?)\b\s*[:\-]?\s*(.*)$"#
    )
    // Program-heading patterns used to (re)anchor the current program.
    private static let minorHeadingRegex = try? NSRegularExpression(
        pattern: #"^Minor in ([A-Za-z].{2,70})$"#, options: [.caseInsensitive]
    )
    private static let majorHeadingRegex = try? NSRegularExpression(
        pattern: #"^Major in ([A-Za-z].{2,70})$"#
    )
    private static let advCertHeadingRegex = try? NSRegularExpression(
        pattern: #"(?i)^Advanced certificate in ([A-Za-z].{2,70})$"#
    )
    private static let degreeProgramHeadingRegex = try? NSRegularExpression(
        pattern: #"(?i)degree programs?\s*(?:in|for|:)?\s+([A-Za-z].{2,80})$"#
    )
    private static let catalogProgramSuffixRegex = try? NSRegularExpression(
        pattern: #"(?i)^(.{3,90}?)\s+(?:degree\s+)?program\s*$"#
    )
    private static let graduateDegreeInRegex = try? NSRegularExpression(
        pattern: #"(?i)^(master|bachelor|doctor)\s+of\s+.+?\s+in\s+(.{3,70})$"#
    )
    private static let ugDegreeInRegex = try? NSRegularExpression(
        pattern: #"(?i)^(B\.?A\.?|B\.?S\.?|B\.?B\.?A\.?|B\.?F\.?A\.?|B\.?M(?:us)?\.?)\s+in\s+(.{3,70})$"#
    )
    private static let separatorRegex = try? NSRegularExpression(pattern: #"^[-–—_=]{3,}$"#)
    /// Prose blocks longer than this are almost certainly running past the actual
    /// requirement section into unrelated catalog text; cap to keep capture tight.
    private static let maxProseLines = 40

    private enum BlockStyle { case table, prose }

    private struct AnchoredGroup {
        let program: String
        let degreeType: String?
        var category: String
        var style: BlockStyle
        var declaredCredits: Int?
        var selectCount: Int?
        var courses: [ParsedRow] = []
        var proseLines: [String] = []
    }

    static func extractAnchoredRequirements(
        lines: [CatalogPDFLine],
        knownPrograms: [ScrapedProgram],
        courseCatalog: [CatalogCourse],
        subjectNameToCode: [String: String]
    ) -> [DegreeRequirement] {
        guard !lines.isEmpty else { return [] }
        let lookup = buildProgramLookup(knownPrograms)
        let titleByCode = Dictionary(
            courseCatalog.map { ($0.courseCode, $0.title) },
            uniquingKeysWith: { first, _ in first }
        )
        let knownCodes = Set(courseCatalog.map { $0.courseCode })

        var output: [DegreeRequirement] = []
        var currentProgram: ProgramRef?
        var group: AnchoredGroup?

        func closeGroup() {
            defer { group = nil }
            guard let g = group else { return }
            if let req = materialize(g, titleByCode: titleByCode) { output.append(req) }
        }

        let normalizedLines: [String] = lines.map {
            $0.text
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for line in normalizedLines {
            guard !line.isEmpty else { continue }

            // 1) Re-anchor on a program heading.
            if let ref = resolveProgramHeading(line, lookup: lookup) {
                closeGroup()
                currentProgram = ref
                continue
            }
            guard let program = currentProgram else { continue }

            // 2) Block openers.
            if let cmu = parseCMUBlock(line) {
                closeGroup()
                group = AnchoredGroup(program: program.name, degreeType: program.degreeType,
                                      category: cmu.name, style: .table, declaredCredits: cmu.units, selectCount: nil)
                continue
            }
            if let prose = parseProseHeader(line) {
                closeGroup()
                group = AnchoredGroup(program: program.name, degreeType: program.degreeType,
                                      category: prose.category, style: .prose,
                                      declaredCredits: prose.credits, selectCount: nil)
                continue
            }
            if program.isMinor, let credits = parseStudentsMustCompleteCredits(line) {
                closeGroup()
                group = AnchoredGroup(program: program.name, degreeType: program.degreeType,
                                      category: "Requirements", style: .prose,
                                      declaredCredits: credits, selectCount: nil)
                group?.proseLines.append(line)
                continue
            }
            if isStrictCategoryHeading(line) {
                closeGroup()
                group = AnchoredGroup(program: program.name, degreeType: program.degreeType,
                                      category: line, style: .table, declaredCredits: nil,
                                      selectCount: selectCount(from: line))
                continue
            }

            guard group != nil else { continue }

            // 3) Body lines for the open group.
            if group!.style == .prose {
                if isSeparatorLine(line) {
                    // A separator after content closes the prose block.
                    if !group!.proseLines.isEmpty { closeGroup() }
                    continue
                }
                if let row = parseAnyCodedRow(line) {
                    group!.courses.append(row)
                }
                group!.proseLines.append(line)
                resolveProseCourses(in: line, subjectNameToCode: subjectNameToCode,
                                    knownCodes: knownCodes, into: &group!.courses)
                if group!.proseLines.count > maxProseLines { closeGroup() }
            } else {
                if let row = parseAnyTableRow(line) {
                    group!.courses.append(row)
                    if group!.courses.count > maxCoursesPerGroup {
                        group!.courses = []
                        group = nil
                        currentProgram = nil
                    }
                } else if let credits = Int(line),
                          let last = group!.courses.indices.last,
                          group!.courses[last].credits == nil {
                    group!.courses[last].credits = credits
                }
            }
        }
        closeGroup()
        return output
    }

    private static func materialize(
        _ g: AnchoredGroup,
        titleByCode: [String: String]
    ) -> DegreeRequirement? {
        let detailed: [CourseDetail] = g.courses.map { row in
            let resolvedTitle = row.title?.isEmpty == false ? row.title : titleByCode[row.code]
            return CourseDetail(code: row.code, title: resolvedTitle, credits: row.credits.map(String.init))
        }
        if g.style == .prose {
            let prose = g.proseLines.joined(separator: " ")
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // A prose block must carry either captured text or resolved courses.
            guard !prose.isEmpty || !detailed.isEmpty else { return nil }
            let credits = g.declaredCredits ?? detailed.compactMap { Int($0.credits ?? "") }.reduce(0, +)
            guard credits <= maxCreditsPerGroup else { return nil }
            return DegreeRequirement(
                degreeType: g.degreeType ?? "",
                major: g.program,
                category: cleanCategory(g.category),
                requiredCourses: detailed.isEmpty ? nil : detailed.map(\.code),
                requiredCoursesDetailed: detailed.isEmpty ? nil : detailed,
                creditsRequired: credits,
                description: String(prose.prefix(1600)),
                selectFrom: nil,
                selectFromDetailed: nil,
                selectCount: nil,
                requirementPredicate: detailed.isEmpty ? nil : .all(detailed.map { .course($0) }),
                requirementKind: .prose,
                displayTitle: cleanCategory(g.category)
            )
        }
        // Table style (CMU units / generic category).
        guard !g.courses.isEmpty, g.courses.count <= maxCoursesPerGroup else { return nil }
        let isSelective = g.selectCount != nil
        let credits = g.declaredCredits
            ?? (isSelective
                ? selectedCreditTarget(courses: g.courses, selectCount: g.selectCount ?? 1)
                : g.courses.compactMap { $0.credits }.reduce(0, +))
        guard credits <= maxCreditsPerGroup else { return nil }
        return DegreeRequirement(
            degreeType: g.degreeType ?? "",
            major: g.program,
            category: cleanCategory(g.category),
            requiredCourses: isSelective ? nil : detailed.map(\.code),
            requiredCoursesDetailed: isSelective ? nil : detailed,
            creditsRequired: credits,
            description: nil,
            selectFrom: isSelective ? detailed.map(\.code) : nil,
            selectFromDetailed: isSelective ? detailed : nil,
            selectCount: g.selectCount,
            requirementPredicate: isSelective
                ? .any(detailed.map { .course($0) }, selectCount: g.selectCount)
                : .all(detailed.map { .course($0) }),
            requirementKind: isSelective ? .chooseOne : .courseList,
            displayTitle: cleanCategory(g.category)
        )
    }

    // MARK: - Strategy B helpers

    private static func resolveProgramHeading(_ line: String, lookup: [String: ProgramRef]) -> ProgramRef? {
        guard line.count <= 110 else { return nil }
        if let reject = runningHeaderRejectRegex {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if reject.firstMatch(in: line, range: range) != nil { return nil }
        }
        if let ref = bestProgramMatch(for: line, lookup: lookup, programs: nil, minimumScore: 1.0) {
            return ref
        }
        if let stripped = stripLeadingDegreeToken(from: line),
           let ref = bestProgramMatch(for: stripped, lookup: lookup, programs: nil, minimumScore: 0.72) {
            return ref
        }
        // Pattern headings carrying the program name (Brooklyn / CMU minor lists).
        let candidates = [minorHeadingRegex, majorHeadingRegex, advCertHeadingRegex, degreeProgramHeadingRegex]
        for regex in candidates {
            guard let name = firstCapture(regex, in: line) else { continue }
            if let ref = bestProgramMatch(for: name, lookup: lookup, programs: nil, minimumScore: 0.72) {
                return ref
            }
        }
        if let name = firstCapture(catalogProgramSuffixRegex, in: line),
           let ref = bestProgramMatch(for: name, lookup: lookup, programs: nil, minimumScore: 0.72) {
            return ref
        }
        if let name = firstCapture(graduateDegreeInRegex, in: line),
           let ref = bestProgramMatch(for: name, lookup: lookup, programs: nil, minimumScore: 0.72) {
            return ref
        }
        if let name = firstCapture(ugDegreeInRegex, in: line),
           let ref = bestProgramMatch(for: name, lookup: lookup, programs: nil, minimumScore: 0.72) {
            return ref
        }
        return bestProgramMatch(for: line, lookup: lookup, programs: nil, minimumScore: 0.78)
    }

    private static func matchKnownProgram(_ rawName: String, lookup: [String: ProgramRef]) -> ProgramRef? {
        bestProgramMatch(for: rawName, lookup: lookup, programs: nil, minimumScore: 0.72)
    }

    private static func parseProseHeader(_ line: String) -> (category: String, credits: Int?)? {
        guard line.count <= 90 else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        if let reject = reqHeaderRejectRegex, reject.firstMatch(in: line, range: range) != nil {
            return nil
        }
        func creditsInLine() -> Int? {
            guard let cr = creditsAnywhereRegex,
                  let cm = cr.firstMatch(in: line, range: range), cm.numberOfRanges >= 2,
                  let cgr = Range(cm.range(at: 1), in: line) else { return nil }
            return Int(line[cgr])
        }
        if let regex = reqHeaderPrefixRegex,
           let m = regex.firstMatch(in: line, range: range), m.numberOfRanges >= 2,
           let catR = Range(m.range(at: 1), in: line) {
            let category = String(line[catR]).trimmingCharacters(in: .whitespaces)
            var credits = (m.numberOfRanges >= 3) ? Range(m.range(at: 2), in: line).flatMap({ Int(line[$0]) }) : nil
            if credits == nil { credits = creditsInLine() }
            return (category, credits)
        }
        if let regex = reqHeaderForRegex,
           let m = regex.firstMatch(in: line, range: range),
           let catR = Range(m.range(at: 1), in: line) {
            return (String(line[catR]).trimmingCharacters(in: .whitespaces), creditsInLine())
        }
        if let regex = programOfCreditsRegex,
           regex.firstMatch(in: line, range: range) != nil {
            return ("Requirements", creditsInLine())
        }
        return nil
    }

    private static func parseStudentsMustCompleteCredits(_ line: String) -> Int? {
        guard line.count <= 120, let regex = studentsMustCompleteRegex else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard regex.firstMatch(in: line, range: range) != nil else { return nil }
        guard let cr = creditsAnywhereRegex,
              let cm = cr.firstMatch(in: line, range: range), cm.numberOfRanges >= 2,
              let cgr = Range(cm.range(at: 1), in: line) else { return nil }
        return Int(line[cgr])
    }

    private static func parseCMUBlock(_ line: String) -> (name: String, units: Int)? {
        guard line.count <= 100, let regex = cmuBlockRegex else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let m = regex.firstMatch(in: line, range: range), m.numberOfRanges >= 4,
              let nameR = Range(m.range(at: 1), in: line),
              let unitsR = Range(m.range(at: 3), in: line) else { return nil }
        let name = String(line[nameR]).trimmingCharacters(in: CharacterSet(charactersIn: " ,:;-"))
        let units = Int(line[unitsR]) ?? 0
        guard !name.isEmpty else { return nil }
        return (name, units)
    }

    /// Fordham `SUBJ 1234 …` rows and CMU `##-### …` rows.
    private static func parseAnyTableRow(_ line: String) -> ParsedRow? {
        if let row = parseCourseRow(line) { return row }
        return parseCMURow(line)
    }

    /// Coded rows that may appear inside an otherwise-prose block (bullets or plain codes).
    private static func parseAnyCodedRow(_ line: String) -> ParsedRow? {
        if let regex = bulletCodeRegex {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let m = regex.firstMatch(in: line, range: range), m.numberOfRanges >= 4,
               let subjR = Range(m.range(at: 1), in: line),
               let numR = Range(m.range(at: 2), in: line) {
                let code = "\(line[subjR]) \(line[numR])".uppercased()
                let title = Range(m.range(at: 3), in: line).map {
                    String(line[$0]).trimmingCharacters(in: .whitespaces)
                }
                return ParsedRow(code: code, title: (title?.isEmpty == false) ? title : nil, credits: nil)
            }
        }
        return parseCourseRow(line) ?? parseCMURow(line)
    }

    private static func parseCMURow(_ line: String) -> ParsedRow? {
        if let regex = cmuRowWithUnitsRegex {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let m = regex.firstMatch(in: line, range: range), m.numberOfRanges >= 4,
               let codeR = Range(m.range(at: 1), in: line),
               let titleR = Range(m.range(at: 2), in: line),
               let unitR = Range(m.range(at: 3), in: line) {
                let title = String(line[titleR]).trimmingCharacters(in: .whitespaces)
                let credits = Int((Double(line[unitR]) ?? 0).rounded())
                return ParsedRow(code: String(line[codeR]).uppercased(), title: title.isEmpty ? nil : title, credits: credits)
            }
        }
        if let regex = cmuRowNoUnitsRegex {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if let m = regex.firstMatch(in: line, range: range), m.numberOfRanges >= 3,
               let codeR = Range(m.range(at: 1), in: line),
               let titleR = Range(m.range(at: 2), in: line) {
                let title = String(line[titleR]).trimmingCharacters(in: .whitespaces)
                return ParsedRow(code: String(line[codeR]).uppercased(), title: title.isEmpty ? nil : title, credits: nil)
            }
        }
        return nil
    }

    /// Best-effort: resolve "Accounting 2001"-style prose mentions to a course code
    /// using the subject-name → subject-code map, but only when the resolved code
    /// exists in the catalog (so prose noise is rejected).
    private static func resolveProseCourses(
        in line: String,
        subjectNameToCode: [String: String],
        knownCodes: Set<String>,
        into courses: inout [ParsedRow]
    ) {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        var existing = Set(courses.map(\.code))

        func appendIfKnown(_ full: String) {
            guard knownCodes.contains(full), existing.insert(full).inserted else { return }
            courses.append(ParsedRow(code: full, title: nil, credits: nil))
        }

        // Inline catalog codes, e.g. "AMST 1001", "HIST 3458".
        if let coded = try? NSRegularExpression(pattern: #"\b([A-Z]{2,6})\s+(\d{3,4}[A-Z]?)\b"#) {
            coded.enumerateMatches(in: line, range: range) { match, _, _ in
                guard let match, match.numberOfRanges >= 3,
                      let subjR = Range(match.range(at: 1), in: line),
                      let numR = Range(match.range(at: 2), in: line) else { return }
                appendIfKnown("\(line[subjR]) \(line[numR])".uppercased())
            }
        }

        // Full subject-name mentions, e.g. "Accounting 3101" -> "ACCT 3101".
        guard !subjectNameToCode.isEmpty,
              let regex = try? NSRegularExpression(
                pattern: #"([A-Z][a-zA-Z&'/]+(?:\s+(?:and\s+)?[A-Z][a-zA-Z&'/]+){0,3})\s+(\d{3,4}[A-Z]?)"#
              ) else { return }
        regex.enumerateMatches(in: line, range: range) { match, _, _ in
            guard let match, match.numberOfRanges >= 3,
                  let nameR = Range(match.range(at: 1), in: line),
                  let numR = Range(match.range(at: 2), in: line) else { return }
            let subject = String(line[nameR]).trimmingCharacters(in: .whitespaces).lowercased()
            guard let code = subjectNameToCode[subject] else { return }
            appendIfKnown("\(code) \(line[numR])".uppercased())
        }
    }

    /// A category heading that is safe to trust when walking *raw* document lines
    /// (Strategy B), where the looser `isCategoryHeading` would otherwise promote
    /// ordinary prose ("Elective. Every first year student…") into a category.
    private static func isStrictCategoryHeading(_ line: String) -> Bool {
        guard line.count <= 60, isCategoryHeading(line) else { return false }
        // Full sentences / prose: a period anywhere but the final character.
        let body = line.hasSuffix(".") ? String(line.dropLast()) : line
        if body.contains(".") { return false }
        if line.split(separator: " ").count > 8 { return false }
        // Address / phone / catalog numbers.
        if line.range(of: #"\b\d{3,}\b"#, options: .regularExpression) != nil { return false }
        let lower = line.lowercased()
        for term in ["office", "phone", "director", "chair", "building", "hall", "room", "email", "website"] {
            if lower.contains(term) { return false }
        }
        // Connective-laden long phrases are prose, not headings.
        if line.count > 28 {
            for connective in [" of ", " with ", " to the ", " that ", " which ", " from a "] where lower.contains(connective) {
                return false
            }
        }
        return true
    }

    private static func isSeparatorLine(_ line: String) -> Bool {
        guard let regex = separatorRegex else { return false }
        return regex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)) != nil
    }

    private static func cleanCategory(_ category: String) -> String {
        let trimmed = category.trimmingCharacters(in: CharacterSet(charactersIn: " .,:;-"))
        return trimmed.isEmpty ? "Requirements" : trimmed
    }

    private static func firstCapture(_ regex: NSRegularExpression?, in line: String) -> String? {
        guard let regex else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let m = regex.firstMatch(in: line, range: range), m.numberOfRanges >= 2,
              let r = Range(m.range(at: 1), in: line) else { return nil }
        return String(line[r]).trimmingCharacters(in: .whitespaces)
    }
}
