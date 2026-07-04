// CareerResumeParseSanitizer.swift
// Feature: Career / ResumeParsing
// Purpose: Ground parsed resume fields in source text; repair mis-grouped entries and split bullets.

import Foundation

enum CareerResumeParseSanitizer {
    static func sanitize(_ profile: CareerResumeStructuredProfile, sourceText: String) -> CareerResumeStructuredProfile {
        var sanitized = profile
        let source = sourceText.lowercased()

        sanitized.skills = profile.skills.filter { isGrounded($0, in: source) }
        sanitized.skillGroups = profile.skillGroups.compactMap { group in
            let skills = group.skills.filter { isGrounded($0, in: source) }
            guard !skills.isEmpty else { return nil }
            return CareerResumeStructuredProfile.SkillGroup(category: group.category, skills: skills)
        }
        sanitized.certifications = profile.certifications.filter { isGrounded($0, in: source) }
        sanitized.experience = repairExperienceEntries(profile.experience, sourceText: sourceText)
        sanitized.projects = repairProjectEntries(profile.projects, sourceText: sourceText)
        sanitized.education = repairEducationEntries(profile.education, sourceText: sourceText)
        return sanitized
    }

    // MARK: - Experience

    private static func repairExperienceEntries(
        _ entries: [CareerResumeStructuredProfile.Entry],
        sourceText: String
    ) -> [CareerResumeStructuredProfile.Entry] {
        entries
            .flatMap { splitExperienceEntry($0, sourceText: sourceText) }
            .filter { !$0.isEmpty }
    }

    private static func splitExperienceEntry(
        _ entry: CareerResumeStructuredProfile.Entry,
        sourceText: String
    ) -> [CareerResumeStructuredProfile.Entry] {
        var expanded: [CareerResumeStructuredProfile.Entry] = []
        var headings = entry.headingLines
        var bullets = entry.bullets

        while let index = bullets.firstIndex(where: { isLikelyExperienceHeading($0) }) {
            let promotedHeading = bullets[index]
            let leadingBullets = Array(bullets.prefix(index)).filter { !$0.isEmpty }
            if !headings.isEmpty || !leadingBullets.isEmpty {
                expanded.append(
                    cleanedEntry(
                        headingLines: headings,
                        bullets: mergeFragmentedBullets(leadingBullets),
                        sourceText: sourceText
                    )
                )
            }
            headings = [promotedHeading]
            bullets = Array(bullets.dropFirst(index + 1))
        }

        expanded.append(
            cleanedEntry(
                headingLines: headings,
                bullets: mergeFragmentedBullets(bullets),
                sourceText: sourceText
            )
        )
        return expanded.filter { !$0.isEmpty }
    }

    // MARK: - Projects

    private static func repairProjectEntries(
        _ entries: [CareerResumeStructuredProfile.Entry],
        sourceText: String
    ) -> [CareerResumeStructuredProfile.Entry] {
        var expanded: [CareerResumeStructuredProfile.Entry] = []

        for entry in entries {
            var headings = entry.headingLines
            var bullets = entry.bullets

            while let index = bullets.firstIndex(where: { isLikelyProjectHeading($0) }) {
                let promotedHeading = bullets[index]
                let leadingBullets = Array(bullets.prefix(index)).filter { !$0.isEmpty }
                if !headings.isEmpty || !leadingBullets.isEmpty {
                    expanded.append(
                        cleanedEntry(
                            headingLines: headings,
                            bullets: mergeFragmentedBullets(leadingBullets),
                            sourceText: sourceText
                        )
                    )
                }
                headings = [promotedHeading]
                bullets = Array(bullets.dropFirst(index + 1))
            }

            expanded.append(
                cleanedEntry(
                    headingLines: headings,
                    bullets: mergeFragmentedBullets(bullets),
                    sourceText: sourceText
                )
            )
        }

        return expanded.filter { !$0.isEmpty }
    }

    // MARK: - Education

    private static func repairEducationEntries(
        _ entries: [CareerResumeStructuredProfile.Entry],
        sourceText: String
    ) -> [CareerResumeStructuredProfile.Entry] {
        entries
            .flatMap { splitEducationByInstitution($0) }
            .compactMap { entry -> CareerResumeStructuredProfile.Entry? in
                let headings = entry.headingLines
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && !isBulletOnlyLine($0) }
                let bullets = mergeFragmentedBullets(splitEducationDetailLines(entry.bullets))
                    .filter { isGrounded($0, in: sourceText.lowercased()) }

                guard !headings.isEmpty || !bullets.isEmpty else { return nil }
                let primary = headings.first?.lowercased() ?? ""
                if primary == "school" && !sourceText.localizedCaseInsensitiveContains("school") {
                    return nil
                }
                return .init(headingLines: headings, bullets: bullets)
            }
            .filter { !$0.isEmpty }
    }

    private static func splitEducationByInstitution(
        _ entry: CareerResumeStructuredProfile.Entry
    ) -> [CareerResumeStructuredProfile.Entry] {
        let lines = (entry.headingLines + entry.bullets)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isBulletOnlyLine($0) }

        var institutions: [(String, [String])] = []
        var currentInstitution: String?
        var details: [String] = []

        func flush() {
            guard let institution = currentInstitution else { return }
            institutions.append((institution, details))
            details = []
        }

        for line in lines {
            if isLikelyEducationInstitution(line) {
                if currentInstitution != nil {
                    flush()
                }
                currentInstitution = line
            } else {
                details.append(line)
            }
        }
        flush()

        guard institutions.count > 1 else { return [entry] }
        return institutions.map { .init(headingLines: [$0.0], bullets: $0.1) }
    }

    private static func splitEducationDetailLines(_ lines: [String]) -> [String] {
        var result: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed.count > 140,
               trimmed.localizedCaseInsensitiveContains("gpa:"),
               trimmed.localizedCaseInsensitiveContains("coursework:") {
                result.append(contentsOf: splitCombinedEducationLine(trimmed))
            } else {
                result.append(trimmed)
            }
        }
        return result
    }

    private static func splitCombinedEducationLine(_ line: String) -> [String] {
        var parts: [String] = []
        let markers = ["GPA:", "Coursework:", "Awards:", "Minors:", "Graduated:"]
        var remaining = line

        while let marker = markers.first(where: { remaining.localizedCaseInsensitiveContains($0) }) {
            guard let range = remaining.range(of: marker, options: [.caseInsensitive, .diacriticInsensitive]) else {
                break
            }
            let prefix = String(remaining[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty {
                parts.append(prefix.trimmingCharacters(in: CharacterSet(charactersIn: ";|")))
            }
            remaining = String(remaining[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if !remaining.isEmpty {
            parts.append(remaining)
        }
        return parts.filter { !$0.isEmpty }
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

    // MARK: - Entry cleanup

    private static func cleanedEntry(
        headingLines: [String],
        bullets: [String],
        sourceText: String
    ) -> CareerResumeStructuredProfile.Entry {
        let source = sourceText.lowercased()
        let cleanedHeadings = headingLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isBulletOnlyLine($0) }
        let cleanedBullets = bullets
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && isGrounded($0, in: source) }

        return .init(headingLines: cleanedHeadings, bullets: cleanedBullets)
    }

    // MARK: - Bullet merging

    static func mergeFragmentedBullets(_ bullets: [String]) -> [String] {
        var merged: [String] = []
        for raw in bullets {
            let bullet = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bullet.isEmpty else { continue }

            if let last = merged.last, shouldMergeContinuation(previous: last, next: bullet) {
                merged[merged.count - 1] = joinBulletContinuation(last, bullet)
            } else {
                merged.append(bullet)
            }
        }
        return merged
    }

    private static func shouldMergeContinuation(previous: String, next: String) -> Bool {
        if isEducationOrMetadataLine(previous) || isEducationOrMetadataLine(next) {
            return false
        }
        if startsWithActionVerb(previous), startsWithActionVerb(next) {
            return false
        }
        if previous.hasSuffix(".") {
            return false
        }
        if next.first?.isNumber == true { return true }
        if let first = next.first, first.isLowercase { return true }
        if previous.hasSuffix(",") || previous.hasSuffix("(") { return true }
        if !startsWithActionVerb(next) { return true }
        return false
    }

    private static func isEducationOrMetadataLine(_ line: String) -> Bool {
        let lower = line.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = [
            "gpa:", "coursework:", "graduated:", "bachelor", "master", "associate", "doctor",
            "minor", "major:", "awards:", "honors:", "degree:",
        ]
        if prefixes.contains(where: { lower.hasPrefix($0) }) { return true }
        if lower.contains("bachelor of") || lower.contains("bachelors of") || lower.contains("master of") {
            return true
        }
        return lower.range(
            of: #"(?i)\b(university|college|institute)\b"#,
            options: .regularExpression
        ) != nil && !lower.hasPrefix("coursework:")
    }

    private static func joinBulletContinuation(_ previous: String, _ next: String) -> String {
        var prev = previous
        if prev.hasSuffix("-") || prev.hasSuffix("–") {
            prev.removeLast()
            return prev + next
        }
        return prev + " " + next
    }

    // MARK: - Heading detection

    private static func isLikelyExperienceHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(" - ") || trimmed.contains(" – ") || trimmed.contains(" — ") else {
            return false
        }
        return trimmed.range(
            of: #"(?i)\b(intern|analyst|consultant|specialist|associate|coordinator|manager|engineer)\b"#,
            options: .regularExpression
        ) != nil
    }

    private static func isLikelyProjectHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(
            of: #"(?i)\b(capstone|lab|deployment|reconstruction)\b"#, options: .regularExpression
        ) != nil
        && trimmed.range(
            of: #"(?i)\b(fall|spring|summer|winter|january|february|march|april|may|june|july|august|september|october|november|december)\b"#,
            options: .regularExpression
        ) != nil
    }

    // MARK: - Grounding

    private static func isGrounded(_ value: String, in sourceLowercased: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if sourceLowercased.contains(trimmed.lowercased()) {
            return true
        }

        let alnum = trimmed.lowercased().filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
        let compact = alnum.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if compact.count >= 8, sourceLowercased.contains(compact) {
            return true
        }

        let tokens = trimmed.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 }
        guard !tokens.isEmpty else { return false }

        let matched = tokens.filter { sourceLowercased.contains($0) }.count
        return Double(matched) / Double(tokens.count) >= 0.72
    }

    private static func isBulletOnlyLine(_ line: String) -> Bool {
        line.range(of: #"^[•◦▪▫●‣·∙\*\s\-–—]+$"#, options: .regularExpression) != nil
    }

    private static func startsWithActionVerb(_ line: String) -> Bool {
        let lower = line.lowercased()
        let verbs = [
            "assessed", "supported", "analyzed", "authored", "resolved", "architected", "deployed",
            "conducted", "executed", "designed", "compiled", "created", "managed", "developed",
        ]
        return verbs.contains { lower.hasPrefix($0) }
    }
}
