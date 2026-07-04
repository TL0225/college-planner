// CareerResumeStructuredParser.swift
// Feature: Career
// Purpose: Deterministic, offline extraction of structured resume fields
//          (name, contact, location, education, experience, projects, skills)
//          from the plain text produced by CareerResumeTextExtractor.

import Foundation

// MARK: - Structured profile model

/// Everything the resume parser was able to recover from an uploaded resume.
/// Persisted as JSON inside `CareerResumeMetadataV1.structuredSectionsJSON`.
struct CareerResumeStructuredProfile: Codable, Equatable, Sendable {
    /// A single block within a section (a job, a degree, a project).
    struct Entry: Codable, Equatable, Sendable {
        /// Title / organization / date lines that precede the bullet points.
        var headingLines: [String]
        /// Bullet points / responsibilities.
        var bullets: [String]

        var isEmpty: Bool { headingLines.isEmpty && bullets.isEmpty }
    }

    /// Categorized skills (e.g. "Security & Compliance: NIST, ISO 27001").
    struct SkillGroup: Codable, Equatable, Sendable {
        var category: String
        var skills: [String]
    }

    /// A section the parser recognized but couldn't map to a known category.
    struct FreeSection: Codable, Equatable, Sendable {
        var title: String
        var lines: [String]
    }

    var name: String?
    var email: String?
    var phone: String?
    var location: String?
    var links: [String]
    var summary: String?
    var skills: [String]
    var skillGroups: [SkillGroup]
    var education: [Entry]
    var experience: [Entry]
    var projects: [Entry]
    var certifications: [String]
    var otherSections: [FreeSection]

    init(
        name: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        location: String? = nil,
        links: [String] = [],
        summary: String? = nil,
        skills: [String] = [],
        skillGroups: [SkillGroup] = [],
        education: [Entry] = [],
        experience: [Entry] = [],
        projects: [Entry] = [],
        certifications: [String] = [],
        otherSections: [FreeSection] = []
    ) {
        self.name = name
        self.email = email
        self.phone = phone
        self.location = location
        self.links = links
        self.summary = summary
        self.skills = skills
        self.skillGroups = skillGroups
        self.education = education
        self.experience = experience
        self.projects = projects
        self.certifications = certifications
        self.otherSections = otherSections
    }

    /// True when the parser recovered no usable structured content at all.
    var hasContent: Bool {
        if name != nil || email != nil || phone != nil || location != nil { return true }
        if !links.isEmpty || !skills.isEmpty || !skillGroups.isEmpty || !certifications.isEmpty { return true }
        if summary != nil { return true }
        if !education.isEmpty || !experience.isEmpty || !projects.isEmpty { return true }
        if !otherSections.isEmpty { return true }
        return false
    }
}

// MARK: - Parser

enum CareerResumeStructuredParser {
    private enum Category {
        case summary, skills, experience, education, projects, certifications
    }

    /// Bullet glyphs that mark a responsibility / detail line.
    private static let bulletPrefixes: [String] = [
        "•", "◦", "▪", "▫", "●", "‣", "·", "∙", "*", "-", "–", "—", "›", "»", "★", "☆"
    ]

    private static let sectionKeywords: [(Category, [String])] = [
        (.summary, ["summary", "professional summary", "profile", "objective", "career objective", "about", "about me", "overview"]),
        (.skills, ["skills", "technical skills", "core skills", "key skills", "technologies", "technical proficiencies", "core competencies", "competencies", "tools", "tools and technologies", "areas of expertise", "expertise", "tech stack"]),
        (.experience, ["experience", "work experience", "professional experience", "employment", "employment history", "work history", "relevant experience", "industry experience"]),
        (.education, ["education", "academic background", "academics", "educational background", "education and training"]),
        (.projects, ["projects", "personal projects", "academic projects", "selected projects", "key projects", "side projects", "notable projects"]),
        (.certifications, ["certifications", "certification", "certificates", "licenses", "licenses and certifications", "awards", "honors", "honors and awards", "achievements", "accomplishments"])
    ]

    static func parse(plainText: String) -> CareerResumeStructuredProfile {
        let lines = normalizedLines(from: plainText)
        guard !lines.isEmpty else { return CareerResumeStructuredProfile() }

        var profile = CareerResumeStructuredProfile()

        // Contact details can appear anywhere; scan the entire document.
        profile.email = firstMatch(in: plainText, pattern: #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#)
        profile.phone = firstMatch(in: plainText, pattern: #"\(?\+?\d{0,3}\)?[\s.\-]?\(?\d{3}\)?[\s.\-]?\d{3}[\s.\-]?\d{4}"#)?
            .trimmingCharacters(in: .whitespaces)
        profile.links = extractLinks(from: plainText)

        // Split into a header preamble and category buckets.
        var preamble: [Line] = []
        var buckets: [Category: [Line]] = [:]
        var freeSections: [(title: String, lines: [Line])] = []
        var current: Category?
        var currentFreeIndex: Int?

        for line in lines {
            if let (category, title) = sectionCategory(for: line.text) {
                currentFreeIndex = nil
                if let category {
                    current = category
                    if buckets[category] == nil { buckets[category] = [] }
                } else {
                    current = nil
                    freeSections.append((title: title, lines: []))
                    currentFreeIndex = freeSections.count - 1
                }
                continue
            }

            if let current {
                buckets[current, default: []].append(line)
            } else if let idx = currentFreeIndex {
                freeSections[idx].lines.append(line)
            } else {
                preamble.append(line)
            }
        }

        parsePreamble(preamble, into: &profile)

        if let summaryLines = buckets[.summary] {
            let text = summaryLines.map { $0.text }.joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            profile.summary = text.isEmpty ? nil : text
        }
        if let skillLines = buckets[.skills] {
            let parsed = parseSkillGroups(skillLines.map(\.text))
            profile.skillGroups = parsed.groups
            profile.skills = parsed.flat
        }
        if let certLines = buckets[.certifications] {
            profile.certifications = certLines
                .map { stripBullet($0.text) }
                .filter { !$0.isEmpty }
        }
        if let expLines = buckets[.experience] {
            profile.experience = groupEntries(expLines)
        }
        if let eduLines = buckets[.education] {
            profile.education = groupEntries(eduLines).map(normalizeEducationEntry)
        }
        if let projectLines = buckets[.projects] {
            profile.projects = groupEntries(projectLines)
        }

        profile.otherSections = freeSections.compactMap { section in
            let cleaned = section.lines.map { stripBullet($0.text) }.filter { !$0.isEmpty }
            guard !cleaned.isEmpty else { return nil }
            return CareerResumeStructuredProfile.FreeSection(title: section.title, lines: cleaned)
        }

        return profile
    }

    // MARK: - Line model

    private struct Line {
        let text: String
        let blankBefore: Bool
    }

    private static func normalizedLines(from text: String) -> [Line] {
        let raw = text.components(separatedBy: .newlines)
        var result: [Line] = []
        var pendingBlank = false
        for entry in raw {
            let trimmed = entry.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                pendingBlank = true
                continue
            }
            result.append(Line(text: trimmed, blankBefore: pendingBlank && !result.isEmpty))
            pendingBlank = false
        }
        return result
    }

    // MARK: - Section detection

    /// Returns the matched category (nil for an unknown-but-real header) and the
    /// display title, or `nil` when the line is ordinary content.
    private static func sectionCategory(for line: String) -> (Category?, String)? {
        let letters = line.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard letters >= 3 else { return nil }
        // Headers are short and don't read like sentences.
        guard line.count <= 42 else { return nil }
        if line.contains("@") { return nil }

        let normalized = line
            .lowercased()
            .replacingOccurrences(of: ":", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty else { return nil }

        for (category, keys) in sectionKeywords where keys.contains(normalized) {
            return (category, prettyHeader(line))
        }

        // ALL-CAPS short standalone headings (e.g. "VOLUNTEERING") are real
        // section headers even if we don't have a category for them.
        let wordCount = normalized.split(separator: " ").count
        let isUpperHeading = line == line.uppercased()
            && wordCount <= 4
            && !line.contains(where: { $0.isNumber })
        if isUpperHeading {
            return (nil, prettyHeader(line))
        }

        return nil
    }

    private static func prettyHeader(_ line: String) -> String {
        let cleaned = line.trimmingCharacters(in: CharacterSet(charactersIn: " :•-–—"))
        if cleaned == cleaned.uppercased() {
            return cleaned.capitalized
        }
        return cleaned
    }

    // MARK: - Preamble (name / location)

    private static func parsePreamble(_ preamble: [Line], into profile: inout CareerResumeStructuredProfile) {
        let segments = preamble.prefix(6).flatMap { splitContactSegments($0.text) }

        // Name: first segment that looks like a person's name.
        if let name = segments.first(where: { isLikelyName($0) }) {
            profile.name = name
        }

        // Location: a "City, ST" / "City, Country" style segment.
        if let location = segments.first(where: { isLikelyLocation($0) && $0 != profile.name }) {
            profile.location = location
        }
    }

    private static func splitContactSegments(_ line: String) -> [String] {
        line
            .components(separatedBy: CharacterSet(charactersIn: "|•·‣"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func isLikelyName(_ segment: String) -> Bool {
        if segment.contains("@") { return false }
        if segment.contains("http") || segment.lowercased().contains("www.") { return false }
        if segment.contains(where: { $0.isNumber }) { return false }
        let words = segment.split(separator: " ")
        guard (1...4).contains(words.count) else { return false }
        // Mostly letters and reasonable length.
        let letters = segment.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard letters >= 2, segment.count <= 48 else { return false }
        // Avoid section-y words.
        let lowered = segment.lowercased()
        let banned = ["resume", "curriculum", "vitae", "summary", "experience", "education", "skills"]
        if banned.contains(where: { lowered.contains($0) }) { return false }
        return true
    }

    private static func isLikelyLocation(_ segment: String) -> Bool {
        if segment.contains("@") || segment.contains("http") { return false }
        guard segment.contains(",") else { return false }
        if segment.count > 48 { return false }
        // "City, ST" or "City, Country"
        return segment.range(
            of: #"^[A-Za-z .'\-]+,\s*[A-Za-z]{2,}\.?$"#,
            options: .regularExpression
        ) != nil
    }

    // MARK: - Skills / links tokenizing

    private static func tokenizeSkills(_ lines: [String]) -> [String] {
        var tokens: [String] = []
        for line in lines {
            let cleaned = stripBullet(line)
            // Strip a "Languages:" style prefix.
            let body: String
            if let colon = cleaned.firstIndex(of: ":") {
                body = String(cleaned[cleaned.index(after: colon)...])
            } else {
                body = cleaned
            }
            let parts = body
                .components(separatedBy: CharacterSet(charactersIn: ",;|·•/\t"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && $0.count <= 40 }
            tokens.append(contentsOf: parts)
        }
        // De-dupe (case-insensitive) preserving order.
        var seen = Set<String>()
        var result: [String] = []
        for token in tokens {
            let key = token.lowercased()
            if seen.insert(key).inserted {
                result.append(token)
            }
        }
        return Array(result.prefix(60))
    }

    private static func extractLinks(from text: String) -> [String] {
        let pattern = #"((https?://)?(www\.)?(linkedin\.com|github\.com|gitlab\.com|behance\.net|dribbble\.com|medium\.com)/[^\s|•,]+)|(https?://[^\s|•,]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        var seen = Set<String>()
        var result: [String] = []
        for match in regex.matches(in: text, options: [], range: range) {
            guard let r = Range(match.range, in: text) else { continue }
            var link = String(text[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,);"))
            if link.lowercased().hasPrefix("www.") { link = "https://" + link }
            if seen.insert(link.lowercased()).inserted {
                result.append(link)
            }
        }
        return Array(result.prefix(8))
    }

    // MARK: - Entry grouping

    private static func groupEntries(_ lines: [Line]) -> [CareerResumeStructuredProfile.Entry] {
        var entries: [CareerResumeStructuredProfile.Entry] = []
        var headingLines: [String] = []
        var bullets: [String] = []
        var collectingBullets = false

        func flush() {
            let normalized = normalizeEntry(headingLines: headingLines, bullets: bullets)
            if !normalized.isEmpty { entries.append(normalized) }
            headingLines = []
            bullets = []
            collectingBullets = false
        }

        for line in lines {
            let text = line.text
            let explicitBullet = isBullet(text)

            if line.blankBefore, !headingLines.isEmpty || !bullets.isEmpty {
                flush()
            }

            if explicitBullet {
                bullets.append(stripBullet(text))
                collectingBullets = true
                continue
            }

            if shouldStartNewEntry(
                line: text,
                headingLineCount: headingLines.count,
                collectingBullets: collectingBullets,
                blankBefore: line.blankBefore
            ) {
                flush()
                headingLines.append(text)
                continue
            }

            if shouldTreatAsHeading(line: text, headingLineCount: headingLines.count, collectingBullets: collectingBullets) {
                if collectingBullets { flush() }
                headingLines.append(text)
                continue
            }

            bullets.append(stripLeadingListMarker(text))
            collectingBullets = true
        }
        flush()
        return entries
    }

    /// Moves descriptive lines mistakenly stored as extra headings into bullets.
    private static func normalizeEntry(
        headingLines: [String],
        bullets: [String]
    ) -> CareerResumeStructuredProfile.Entry {
        var headings = headingLines
        var body = bullets

        while headings.count > 3 {
            body.insert(headings.removeLast(), at: 0)
        }

        if headings.count >= 2 {
            let trailing = Array(headings.dropFirst(2))
            let promoted = trailing.filter { looksLikeBodyLine($0) }
            if !promoted.isEmpty {
                headings = Array(headings.prefix(2)) + trailing.filter { !promoted.contains($0) }
                body = promoted + body
            }
        }

        body = CareerResumeParseSanitizer.mergeFragmentedBullets(body)

        return .init(headingLines: headings, bullets: body)
    }

    private static func shouldStartNewEntry(
        line: String,
        headingLineCount: Int,
        collectingBullets: Bool,
        blankBefore: Bool
    ) -> Bool {
        if isLikelyEducationInstitution(line), headingLineCount > 0 {
            return true
        }
        guard isLikelyPrimaryHeading(line) else { return false }
        if headingLineCount == 0 { return blankBefore || !collectingBullets }
        return collectingBullets || blankBefore || headingLineCount >= 2
    }

    private static func shouldTreatAsHeading(
        line: String,
        headingLineCount: Int,
        collectingBullets: Bool
    ) -> Bool {
        if headingLineCount == 0 { return true }
        if collectingBullets { return false }
        if headingLineCount >= 3 { return false }
        if CareerResumeDateParser.parseDateRange(from: line) != nil { return true }
        if isLikelyPrimaryHeading(line) { return true }
        if headingLineCount == 1, line.count <= 72, !looksLikeBodyLine(line) { return true }
        return false
    }

    private static func isLikelyPrimaryHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if CareerResumeDateParser.parseDateRange(from: trimmed) != nil, trimmed.count <= 120 {
            return true
        }

        if trimmed.range(
            of: #"(?i)\b(spring|summer|fall|winter)\s+20\d{2}\b"#,
            options: .regularExpression
        ) != nil {
            return true
        }

        if trimmed.range(
            of: #"(?i)\b(capstone|thesis|portfolio project|independent study)\b"#,
            options: .regularExpression
        ) != nil {
            return true
        }

        let separators = [" – ", " — ", " - ", " | ", " at "]
        for separator in separators where trimmed.contains(separator) {
            let parts = trimmed.components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if parts.count >= 2, parts[0].count <= 72, !looksLikeBodyLine(trimmed) {
                return true
            }
        }

        return false
    }

    private static func looksLikeBodyLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if isBullet(trimmed) { return true }
        if trimmed.count >= 50 { return true }
        if trimmed.contains(". ") { return true }
        return startsWithActionVerb(trimmed)
    }

    private static func startsWithActionVerb(_ line: String) -> Bool {
        let lower = line.lowercased()
        let verbs = [
            "authored", "executed", "resolved", "developed", "implemented", "managed", "designed",
            "built", "created", "led", "collaborated", "conducted", "analyzed", "automated",
            "deployed", "configured", "compiled", "facilitated", "monitored", "supported",
            "maintained", "performed", "delivered", "coordinated", "assisted", "researched",
            "presented", "streamlined", "integrated", "optimized", "established", "evaluated",
            "identified", "investigated", "produced", "reduced", "increased", "improved",
        ]
        return verbs.contains { lower.hasPrefix($0) }
    }

    private static func splitLongParagraph(_ line: String) -> [String] {
        line.components(separatedBy: ". ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.hasSuffix(".") ? $0 : $0 + "." }
    }

    private static func stripLeadingListMarker(_ line: String) -> String {
        var text = stripBullet(line)
        if text.hasPrefix("*") || text.hasPrefix("●") {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    // MARK: - Education & skills shaping

    private static func normalizeEducationEntry(_ entry: CareerResumeStructuredProfile.Entry) -> CareerResumeStructuredProfile.Entry {
        guard let institution = entry.headingLines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              !institution.isEmpty else {
            return entry
        }
        let detailLines = entry.headingLines.dropFirst().map(stripBullet) + entry.bullets.map(stripBullet)
        let bullets = detailLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return .init(headingLines: [institution], bullets: bullets)
    }

    private static func isLikelyEducationInstitution(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 120 else { return false }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("coursework:") || lower.hasPrefix("gpa:") || lower.hasPrefix("graduated:") {
            return false
        }
        return lower.range(
            of: #"(?i)\b(university|college|institute|school of)\b"#,
            options: .regularExpression
        ) != nil
    }

    private static func parseSkillGroups(_ lines: [String]) -> (groups: [CareerResumeStructuredProfile.SkillGroup], flat: [String]) {
        var groups: [CareerResumeStructuredProfile.SkillGroup] = []
        var flat: [String] = []

        for line in lines {
            let cleaned = stripBullet(line)
            if let colon = cleaned.firstIndex(of: ":") {
                let category = String(cleaned[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
                let body = String(cleaned[cleaned.index(after: colon)...])
                let tokens = body
                    .components(separatedBy: CharacterSet(charactersIn: ",;|"))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && $0.count <= 48 }
                if !category.isEmpty, !tokens.isEmpty {
                    groups.append(.init(category: category, skills: tokens))
                    flat.append(contentsOf: tokens)
                }
            } else {
                flat.append(contentsOf: tokenizeSkills([cleaned]))
            }
        }

        var seen = Set<String>()
        let deduped = flat.filter { token in
            let key = token.lowercased()
            return seen.insert(key).inserted
        }
        return (groups, Array(deduped.prefix(60)))
    }

    // MARK: - Bullets

    private static func isBullet(_ line: String) -> Bool {
        for prefix in bulletPrefixes where line.hasPrefix(prefix) {
            // "-word" without a space is more likely a hyphenated word/range.
            if prefix == "-" || prefix == "–" || prefix == "—" {
                let after = line.dropFirst(prefix.count)
                return after.first == " "
            }
            return true
        }
        return false
    }

    private static func stripBullet(_ line: String) -> String {
        var text = line
        for prefix in bulletPrefixes where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
            break
        }
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " \t•-–—"))
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Regex helper

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let r = Range(match.range, in: text) else { return nil }
        return String(text[r])
    }
}
