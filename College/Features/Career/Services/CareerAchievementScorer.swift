// CareerAchievementScorer.swift
// Feature: Career
// Purpose: Bullet quality signals — metrics, scope, seniority language, title trajectory.

import Foundation

struct AchievementAnalysis: Sendable {
    var achievementScore: Int
    var trajectoryNote: String?
    var seniorityAlignmentNote: String?
}

enum CareerAchievementScorer {
    private static let seniorVerbs: Set<String> = [
        "led", "architected", "owned", "defined", "drove", "established", "directed", "spearheaded"
    ]
    private static let juniorVerbs: Set<String> = [
        "assisted", "helped", "participated", "supported", "executed", "contributed"
    ]

    static func analyze(profile: CareerResumeStructuredProfile?) -> AchievementAnalysis {
        guard let profile else {
            return AchievementAnalysis(achievementScore: 40, trajectoryNote: nil, seniorityAlignmentNote: nil)
        }

        let bullets = (profile.experience + profile.projects).flatMap(\.bullets)
        guard !bullets.isEmpty else {
            return AchievementAnalysis(achievementScore: 30, trajectoryNote: nil, seniorityAlignmentNote: nil)
        }

        let quantified = bullets.filter(isQuantified).count
        let metricDensity = Double(quantified) / Double(bullets.count)
        let scopeScore = min(100, bullets.filter(hasScopeIndicator).count * 25)
        let seniorityRatio = seniorityLanguageRatio(bullets: bullets)
        let metricScore = min(100, Int((metricDensity / 0.3 * 100).rounded()))

        let achievementScore = min(100, Int(
            (Double(metricScore) * 0.45 + Double(scopeScore) * 0.25 + seniorityRatio * 100 * 0.30).rounded()
        ))

        return AchievementAnalysis(
            achievementScore: achievementScore,
            trajectoryNote: trajectoryNote(from: profile.experience),
            seniorityAlignmentNote: seniorityAlignmentNote(from: profile.experience, seniorityRatio: seniorityRatio)
        )
    }

    private static func isQuantified(_ bullet: String) -> Bool {
        let patterns = [
            #"\d+%"#, #"\$\d"#, #"\d+[kmb]?\s*(users|customers|requests|transactions)"#,
            #"team of \d+"#, #"from .+ to .+"#, #"\d+\+?"#
        ]
        let lower = bullet.lowercased()
        return patterns.contains { lower.range(of: $0, options: .regularExpression) != nil }
    }

    private static func hasScopeIndicator(_ bullet: String) -> Bool {
        let lower = bullet.lowercased()
        return lower.range(of: #"team of \d+"#, options: .regularExpression) != nil
            || lower.range(of: #"\$\d"#, options: .regularExpression) != nil
            || lower.range(of: #"\d+[kmb]?\s*(users|customers)"#, options: .regularExpression) != nil
    }

    private static func seniorityLanguageRatio(bullets: [String]) -> Double {
        var senior = 0
        var junior = 0
        for bullet in bullets {
            let words = Set(bullet.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
            if !words.isDisjoint(with: seniorVerbs) { senior += 1 }
            if !words.isDisjoint(with: juniorVerbs) { junior += 1 }
        }
        let total = senior + junior
        guard total > 0 else { return 0.5 }
        return Double(senior) / Double(total)
    }

    private static func trajectoryNote(from experience: [CareerResumeStructuredProfile.Entry]) -> String? {
        let tiers = experience.compactMap { tier(from: $0.headingLines.joined(separator: " ")) }
        guard tiers.count >= 2 else { return nil }
        let delta = tiers.last! - tiers.first!
        if delta >= 2 { return "Strong upward title trajectory across roles." }
        if delta < 0 { return "Title regression detected — consider reframing recent role scope." }
        if tiers.allSatisfy({ $0 == tiers.first }) && tiers.count >= 3 {
            return "Title plateau across 3+ roles — highlight expanded scope or promotions in bullets."
        }
        return nil
    }

    private static func seniorityAlignmentNote(
        from experience: [CareerResumeStructuredProfile.Entry],
        seniorityRatio: Double
    ) -> String? {
        guard let latest = experience.first else { return nil }
        let title = latest.headingLines.joined(separator: " ").lowercased()
        let tier = tier(from: title) ?? 1
        if tier >= 3 && seniorityRatio < 0.35 {
            return "Senior title but junior action verbs — strengthen with Led/Owned/Architected where accurate."
        }
        return nil
    }

    private static func tier(from title: String) -> Int? {
        let lower = title.lowercased()
        if lower.contains("director") || lower.contains("vp") || lower.contains("head of") { return 5 }
        if lower.contains("manager") || lower.contains("lead") { return 4 }
        if lower.contains("senior") || lower.contains("staff") { return 3 }
        if lower.contains("intern") || lower.contains("co-op") || lower.contains("associate") { return 1 }
        return 2
    }
}
