// CareerATSScoringProfile.swift
// Feature: Career
// Purpose: Platform-specific ATS scoring weights and tailoring guidance.

import Foundation

struct CareerATSScoringProfile: Sendable {
    enum KeywordMatchMode: Sendable {
        case exact
        case stemmed
        case semantic
        case contextual
    }

    var name: String
    var keywordWeight: Double
    var semanticWeight: Double
    var experienceWeight: Double
    var achievementWeight: Double
    var llmWeight: Double
    var transferableWeight: Double
    var keywordMatchMode: KeywordMatchMode
    var usePlacementMultipliers: Bool
    var useRequiredSkillGating: Bool
    var platformExplanation: String
    var tailoringAdvice: String
    var keywordBarLabel: String

    static func profile(for platform: JobBoardPlatform) -> CareerATSScoringProfile {
        switch platform {
        case .workday:
            return CareerATSScoringProfile(
                name: "Workday",
                keywordWeight: 0.35, semanticWeight: 0.15, experienceWeight: 0.25,
                achievementWeight: 0.10, llmWeight: 0.15, transferableWeight: 0.10,
                keywordMatchMode: .stemmed, usePlacementMultipliers: true, useRequiredSkillGating: true,
                platformExplanation: "Workday HiredScore ranks candidates by skills and qualifications matching the JD. Skills shown inside experience bullets outweigh a bare skills list.",
                tailoringAdvice: "Use exact JD terminology. Spell out acronyms. Demonstrate each required skill inside a dated role bullet.",
                keywordBarLabel: "Keywords"
            )
        case .greenhouse:
            return CareerATSScoringProfile(
                name: "Greenhouse",
                keywordWeight: 0.15, semanticWeight: 0.20, experienceWeight: 0.25,
                achievementWeight: 0.30, llmWeight: 0.10, transferableWeight: 0.15,
                keywordMatchMode: .semantic, usePlacementMultipliers: false, useRequiredSkillGating: false,
                platformExplanation: "Greenhouse Talent Matching is assistive — recruiters define scorecards. Impact and demonstrated outcomes matter more than keyword density.",
                tailoringAdvice: "Lead with quantified outcomes and scope. Human reviewers read your resume — make bullets easy to scan.",
                keywordBarLabel: "Skill density"
            )
        case .lever:
            return CareerATSScoringProfile(
                name: "Lever",
                keywordWeight: 0.10, semanticWeight: 0.20, experienceWeight: 0.25,
                achievementWeight: 0.15, llmWeight: 0.30, transferableWeight: 0.15,
                keywordMatchMode: .semantic, usePlacementMultipliers: false, useRequiredSkillGating: false,
                platformExplanation: "Lever Talent Fit uses an LLM to evaluate holistic fit. Narrative coherence and conceptual match dominate over keyword stuffing.",
                tailoringAdvice: "Tell a coherent story across roles. Connect adjacent experience to JD requirements in plain language.",
                keywordBarLabel: "Keywords"
            )
        case .oracle:
            return CareerATSScoringProfile(
                name: "Oracle Taleo",
                keywordWeight: 0.45, semanticWeight: 0.05, experienceWeight: 0.25,
                achievementWeight: 0.10, llmWeight: 0.15, transferableWeight: 0.05,
                keywordMatchMode: .exact, usePlacementMultipliers: false, useRequiredSkillGating: true,
                platformExplanation: "Oracle Taleo uses Boolean exact-match keyword search. 'CPA' and 'Certified Public Accountant' are different strings.",
                tailoringAdvice: "Mirror JD phrasing verbatim. Include both acronyms and spelled-out forms for every credential and tool.",
                keywordBarLabel: "Keywords"
            )
        case .icims:
            return CareerATSScoringProfile(
                name: "iCIMS",
                keywordWeight: 0.30, semanticWeight: 0.20, experienceWeight: 0.25,
                achievementWeight: 0.10, llmWeight: 0.15, transferableWeight: 0.10,
                keywordMatchMode: .contextual, usePlacementMultipliers: true, useRequiredSkillGating: false,
                platformExplanation: "iCIMS Role Fit weights skills demonstrated inside experience bullets more heavily than a standalone skills section.",
                tailoringAdvice: "Show each skill in context within a dated role. Recent bullets carry more weight.",
                keywordBarLabel: "Keywords"
            )
        case .talemetry:
            return CareerATSScoringProfile(
                name: "Talemetry",
                keywordWeight: 0.10, semanticWeight: 0.20, experienceWeight: 0.25,
                achievementWeight: 0.15, llmWeight: 0.30, transferableWeight: 0.15,
                keywordMatchMode: .semantic, usePlacementMultipliers: false, useRequiredSkillGating: false,
                platformExplanation: "Employ Inc. Talent Fit evaluates holistic LLM-based fit, similar to Lever.",
                tailoringAdvice: "Focus on narrative fit and transferable skills framing rather than keyword repetition.",
                keywordBarLabel: "Keywords"
            )
        case .builtIn, .jobicy, .remoteOK, .yCombinator, .usajobs, .nycCityJobs, .nyStateJobs:
            return CareerATSScoringProfile(
                name: platform.displayName,
                keywordWeight: 0.25, semanticWeight: 0.25, experienceWeight: 0.25,
                achievementWeight: 0.10, llmWeight: 0.15, transferableWeight: 0.10,
                keywordMatchMode: .semantic, usePlacementMultipliers: false, useRequiredSkillGating: false,
                platformExplanation: "Public job boards link to external apply flows — match scoring uses the scraped job description.",
                tailoringAdvice: "Mirror language from the posting and emphasize skills called out in the description.",
                keywordBarLabel: "Keywords"
            )
        }
    }
}
