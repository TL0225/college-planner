// CatalogPDFBlockClassifier.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogPDFBlockClassifier.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Stage 3: classify text blocks with evidence; never force unknown → program.
enum CatalogPDFBlockClassifier {
    static let defaultProgramThreshold: Float = 0.65

    private static let degreeTokenRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?i)\b(AA|AS|AAS|BA|BS|B\.S\.|B\.A\.|MA|MS|MBA|MENG|MPH|MFA|BFA|BM|JD|MD|PhD|PHD|DMD|DDS|DPT|PHARMD|BACHELOR|MASTER|ASSOCIATE|MINOR)\b"#,
        options: []
    )

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

    static func classify(
        blocks: [CatalogPDFTextBlock],
        sections: [CatalogPDFDocumentSection],
        profile: CatalogPDFProfileData,
        headingPath: [String] = []
    ) -> [CatalogPDFClassifiedBlock] {
        var path = headingPath
        var out: [CatalogPDFClassifiedBlock] = []
        out.reserveCapacity(blocks.count)

        for block in blocks {
            if isLikelyHeadingBlock(block) {
                path = updateHeadingPath(path, heading: block.text)
            }

            let page = block.primaryPage
            let sectionKind = CatalogPDFSectionClassifier.sectionKind(forPage: page, sections: sections)

            let classified = classifyOne(
                block: block,
                sectionKind: sectionKind,
                headingPath: path,
                profile: profile
            )
            out.append(classified)
        }

        return out
    }

    private static func classifyOne(
        block: CatalogPDFTextBlock,
        sectionKind: CatalogPDFSectionKind?,
        headingPath: [String],
        profile: CatalogPDFProfileData
    ) -> CatalogPDFClassifiedBlock {
        let text = block.text
        let lower = text.lowercased()
        var matchedRules: [String] = []
        var positive: [String] = []
        var negative: [String] = []

        let rejectHits = CatalogPDFProgramRejectLexicon.matchesNegative(text)
        if !rejectHits.isEmpty {
            negative.append(contentsOf: rejectHits.map { "reject:\($0)" })
        }

        let programScore = scoreProgramBlock(text: text, lower: lower, sectionKind: sectionKind, profile: profile, positive: &positive, negative: &negative, matchedRules: &matchedRules)

        let threshold = profile.blockRules?.programMinConfidence ?? defaultProgramThreshold

        if programScore >= threshold, sectionKind == .programs || sectionKind == nil {
            if !rejectHits.isEmpty && programScore < threshold + 0.15 {
                matchedRules.append("program_rejected_negative_lexicon")
                return make(block, .unknown, 0.35, sectionKind, headingPath, matchedRules, positive, negative)
            }
            matchedRules.append("program_block")
            return make(block, .program, programScore, sectionKind, headingPath, matchedRules, positive, negative)
        }

        if sectionKind == .policies {
            matchedRules.append("section:policies")
            return make(block, .policy, 0.85, sectionKind, headingPath, matchedRules, positive, negative)
        }

        if hasCourseSignature(text: text, profile: profile) {
            matchedRules.append("course_signature")
            positive.append("course_code_or_credits")
            let conf: Float = sectionKind == .courseDescriptions ? 0.88 : 0.72
            return make(block, .course, conf, sectionKind, headingPath, matchedRules, positive, negative)
        }

        if isLikelyHeadingBlock(block) {
            matchedRules.append("heading_shape")
            return make(block, .heading, 0.9, sectionKind, headingPath, matchedRules, positive, negative)
        }

        if sectionKind == .degreeRequirements {
            matchedRules.append("section:requirements")
            return make(block, .requirement, 0.6, sectionKind, headingPath, matchedRules, positive, negative)
        }

        if programScore > 0.4, !rejectHits.isEmpty {
            matchedRules.append("low_confidence_program_candidate")
            negative.append("rejected_below_threshold")
        }

        return make(block, .unknown, max(0.2, programScore * 0.5), sectionKind, headingPath, matchedRules, positive, negative)
    }

    private static func scoreProgramBlock(
        text: String,
        lower: String,
        sectionKind: CatalogPDFSectionKind?,
        profile: CatalogPDFProfileData,
        positive: inout [String],
        negative: inout [String],
        matchedRules: inout [String]
    ) -> Float {
        var score: Float = 0.25

        if sectionKind == .programs {
            score += 0.25
            matchedRules.append("in_programs_section")
        }

        let lineCount = text.components(separatedBy: .newlines).count
        if lineCount <= 4 {
            score += 0.1
            positive.append("compact_block")
        } else if lineCount > 12 {
            score -= 0.2
            negative.append("long_block")
        }

        if text.count > 280 {
            score -= 0.25
            negative.append("too_long_for_program_title")
        }

        if text.contains(".") && text.count > 120 {
            score -= 0.15
            negative.append("sentence_prose")
        }

        let ns = NSRange(text.startIndex..<text.endIndex, in: text)
        if degreeTokenRegex?.firstMatch(in: text, range: ns) != nil {
            score += 0.35
            positive.append("degree_token")
        }

        if lower.contains("bachelor") || lower.contains("master") || lower.contains("associate") || lower.contains("minor in") || lower.contains("concentration") {
            score += 0.2
            positive.append("degree_words")
        }

        if let patterns = profile.blockRules?.programPositivePatterns {
            for pattern in patterns {
                if let re = try? NSRegularExpression(pattern: pattern, options: []),
                   re.firstMatch(in: text, range: ns) != nil {
                    score += 0.15
                    positive.append("profile:\(pattern)")
                    break
                }
            }
        }

        if CatalogPDFProgramRejectLexicon.hasStrongNegative(text) {
            score -= 0.5
        }

        return min(1.0, max(0, score))
    }

    private static func hasCourseSignature(text: String, profile: CatalogPDFProfileData) -> Bool {
        let ns = NSRange(text.startIndex..<text.endIndex, in: text)

        let patterns = profile.blockRules?.courseCodePatterns ?? profile.courseCodePatterns
        for pattern in patterns {
            if let re = try? NSRegularExpression(pattern: pattern, options: []),
               re.firstMatch(in: text, range: ns) != nil {
                if creditsRegex?.firstMatch(in: text, range: ns) != nil { return true }
                if text.components(separatedBy: .newlines).count <= 6 { return true }
            }
        }

        if courseCodeRegex?.firstMatch(in: text, range: ns) != nil,
           creditsRegex?.firstMatch(in: text, range: ns) != nil {
            return true
        }

        if cmuCourseCodeRegex?.firstMatch(in: text, range: ns) != nil {
            return true
        }

        return false
    }

    private static func isLikelyHeadingBlock(_ block: CatalogPDFTextBlock) -> Bool {
        let lines = block.lines
        guard lines.count == 1 else { return false }
        let text = lines[0].text
        let letters = text.filter { $0.isLetter }
        guard !letters.isEmpty else { return false }
        let upperRatio = Double(letters.filter { $0.isUppercase }.count) / Double(letters.count)
        return upperRatio > 0.8 && text.count < 70
    }

    private static func updateHeadingPath(_ path: [String], heading: String) -> [String] {
        var next = path
        let trimmed = heading.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return next }
        next.append(trimmed)
        if next.count > 6 { next.removeFirst(next.count - 6) }
        return next
    }

    private static func make(
        _ block: CatalogPDFTextBlock,
        _ type: CatalogBlockType,
        _ confidence: Float,
        _ sectionKind: CatalogPDFSectionKind?,
        _ headingPath: [String],
        _ matchedRules: [String],
        _ positive: [String],
        _ negative: [String]
    ) -> CatalogPDFClassifiedBlock {
        CatalogPDFClassifiedBlock(
            block: block,
            type: type,
            confidence: confidence,
            headingPath: headingPath,
            sectionKind: sectionKind,
            evidence: ClassificationEvidence(
                matchedRules: matchedRules,
                positiveSignals: positive,
                negativeSignals: negative,
                sourcePage: block.primaryPage,
                sourceSection: sectionKind?.rawValue,
                sourceText: String(block.text.prefix(500))
            )
        )
    }
}
