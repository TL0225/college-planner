// CareerTransferableSkillsExpander.swift
// Feature: Career
// Purpose: Per-JD-skill gap taxonomy and transferable skill adjacency scoring.

import Foundation
import CollegeCareer

struct SkillsGapTaxonomy: Sendable {
    var entries: [SkillGapEntry]
    var transferableScore: Int
}

enum CareerTransferableSkillsExpander {
    private static let adjacency: [String: [String]] = [
        "customer service": ["communication", "stakeholder management", "conflict resolution", "crm"],
        "customer support": ["communication", "troubleshooting", "ticketing", "sla"],
        "software engineer": ["agile", "debugging", "version control", "code review", "testing"],
        "developer": ["agile", "debugging", "git", "ci/cd"],
        "data analyst": ["sql", "python", "visualization", "statistics", "reporting"],
        "frontend": ["javascript", "react", "css", "html", "ui"],
        "backend": ["api", "databases", "microservices", "rest"],
        "ios": ["swift", "mobile", "xcode", "macos"],
        "mobile": ["ios", "android", "react native", "swift"],
        "intern": ["collaboration", "learning", "cross-functional"],
    ]

    static func analyze(
        requiredSkills: [String],
        profile: CareerResumeStructuredProfile?,
        resumeText: String
    ) -> SkillsGapTaxonomy {
        guard !requiredSkills.isEmpty else {
            return SkillsGapTaxonomy(entries: [], transferableScore: 0)
        }

        let corpus = buildCorpus(profile: profile, resumeText: resumeText)
        let datedBullets = datedBulletEntries(from: profile)
        var entries: [SkillGapEntry] = []
        var directCount = 0
        var transferableCount = 0

        for skill in requiredSkills {
            let entry = classify(skill: skill, corpus: corpus, datedBullets: datedBullets)
            entries.append(entry)
            switch entry.status {
            case "direct": directCount += 1
            case "transferable": transferableCount += 1
            default: break
            }
        }

        let total = requiredSkills.count
        let score = total > 0
            ? Int(((Double(directCount) * 1.0 + Double(transferableCount) * 0.6) / Double(total) * 100).rounded())
            : 0

        return SkillsGapTaxonomy(entries: entries, transferableScore: min(100, score))
    }

    private static func classify(
        skill: String,
        corpus: String,
        datedBullets: [(bullet: String, endedYearsAgo: Int?)]
    ) -> SkillGapEntry {
        let needle = skill.lowercased()
        if let recent = datedBullets.first(where: {
            ($0.endedYearsAgo ?? 0) <= 3 && $0.bullet.lowercased().contains(needle)
        }) {
            return SkillGapEntry(
                skill: skill,
                status: "direct",
                evidenceBullet: recent.bullet,
                recencyNote: "Recent role"
            )
        }
        if let stale = datedBullets.first(where: { $0.bullet.lowercased().contains(needle) }) {
            return SkillGapEntry(
                skill: skill,
                status: "stale",
                evidenceBullet: stale.bullet,
                recencyNote: stale.endedYearsAgo.map { "Last used ~\($0) yr ago" } ?? "Older role"
            )
        }
        if corpus.contains(needle) {
            return SkillGapEntry(skill: skill, status: "direct", evidenceBullet: nil, recencyNote: "Skills section")
        }
        if let bridge = transferableEvidence(for: skill, corpus: corpus) {
            return SkillGapEntry(
                skill: skill,
                status: "transferable",
                evidenceBullet: bridge,
                recencyNote: "Adjacent experience"
            )
        }
        return SkillGapEntry(skill: skill, status: "missing", evidenceBullet: nil, recencyNote: nil)
    }

    private static func transferableEvidence(for skill: String, corpus: String) -> String? {
        let lower = skill.lowercased()
        for (domain, related) in adjacency {
            if lower.contains(domain) || domain.contains(lower) {
                if let hit = related.first(where: { corpus.contains($0) }) {
                    return "Related: \(hit)"
                }
            }
        }
        for (_, related) in adjacency {
            if related.contains(where: { lower.contains($0) || $0.contains(lower) }) {
                if let hit = related.first(where: { corpus.contains($0) && $0 != lower }) {
                    return "Adjacent: \(hit)"
                }
            }
        }
        return nil
    }

    private static func buildCorpus(profile: CareerResumeStructuredProfile?, resumeText: String) -> String {
        var parts: [String] = [resumeText.lowercased()]
        if let profile {
            parts.append(profile.skills.joined(separator: " ").lowercased())
            for entry in profile.experience + profile.projects {
                parts.append((entry.headingLines + entry.bullets).joined(separator: " ").lowercased())
            }
        }
        return parts.joined(separator: "\n")
    }

    private static func datedBulletEntries(
        from profile: CareerResumeStructuredProfile?
    ) -> [(bullet: String, endedYearsAgo: Int?)] {
        guard let profile else { return [] }
        var result: [(String, Int?)] = []
        for entry in profile.experience {
            let yearsAgo = yearsSinceEnd(heading: entry.headingLines.first ?? "")
            for bullet in entry.bullets {
                result.append((bullet, yearsAgo))
            }
        }
        return result
    }

    private static func yearsSinceEnd(heading: String) -> Int? {
        CareerResumeDateParser.yearsSinceEnd(heading: heading)
    }
}
