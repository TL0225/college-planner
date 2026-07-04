// CareerResumeSuggestionService.swift
// Feature: Career
// Purpose: Conservative per-entry LLM bullet rewrites for resume tailoring.

import Foundation
import CollegeCareer

actor CareerResumeSuggestionService {
    static let shared = CareerResumeSuggestionService()

    func generateSuggestions(
        profile: CareerResumeStructuredProfile,
        jobDescription: String,
        jobTitle: String,
        skillsGap: SkillsGapTaxonomy,
        platform: JobBoardPlatform
    ) async -> [CareerResumeSuggestion] {
        let scoringProfile = CareerATSScoringProfile.profile(for: platform)
        let missingSkills = skillsGap.entries.filter { $0.status == "missing" || $0.status == "transferable" }.map(\.skill)
        var suggestions: [CareerResumeSuggestion] = []

        if CareerFoundationModelsJSONService.isAvailable() {
            for entry in profile.experience {
                let entrySuggestions = await generateForEntry(
                    entry: entry,
                    jobTitle: jobTitle,
                    jobDescription: jobDescription,
                    missingSkills: missingSkills,
                    tailoringAdvice: scoringProfile.tailoringAdvice
                )
                suggestions.append(contentsOf: entrySuggestions)
            }
        } else {
            suggestions = offlineFallback(profile: profile, missingSkills: missingSkills)
        }

        return suggestions
            .filter { CareerATSAdviceValidator.validatedTip($0.rationale) != nil || !$0.rationale.isEmpty }
            .sorted { ($0.scoreDeltaEstimate ?? 0) > ($1.scoreDeltaEstimate ?? 0) }
    }

    private func generateForEntry(
        entry: CareerResumeStructuredProfile.Entry,
        jobTitle: String,
        jobDescription: String,
        missingSkills: [String],
        tailoringAdvice: String
    ) async -> [CareerResumeSuggestion] {
        guard !entry.bullets.isEmpty else { return [] }
        let heading = entry.headingLines.joined(separator: " · ")
        let bullets = entry.bullets.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")

        let prompt = """
        Rewrite resume bullets conservatively for this job. Rules:
        1. Do NOT add facts, numbers, companies, or claims not in the original bullet.
        2. If a bullet lacks metrics, emit metricPrompt with proposedBullet="" and rationale only.
        3. Preserve voice; keep length within ±20%.
        4. Mark tier "verify" when uncertain or when adding scope/numbers.
        5. Use type: actionVerbUpgrade | keywordInjection | clarification | conciseness | starExpansion | metricPrompt

        Tailoring advice: \(tailoringAdvice)
        Job title: \(jobTitle)
        Missing/transferable skills to weave when honest: \(missingSkills.prefix(8).joined(separator: ", "))

        Role heading: \(heading)
        Bullets:
        \(bullets)

        Job excerpt:
        \(jobDescription.prefix(4_000))

        Return strict JSON:
        { "suggestions": [
          { "originalBullet": String, "proposedBullet": String, "rationale": String,
            "type": String, "tier": String, "scoreDeltaEstimate": Int }
        ]}
        """

        guard let raw = await CareerFoundationModelsJSONService.generateJSON(prompt: prompt),
              let data = raw.data(using: .utf8)
        else { return [] }

        struct Response: Codable {
            var suggestions: [Payload]?
            struct Payload: Codable {
                var originalBullet: String
                var proposedBullet: String?
                var rationale: String
                var type: String?
                var tier: String?
                var scoreDeltaEstimate: Int?
            }
        }

        guard let decoded = try? JSONDecoder().decode(Response.self, from: data),
              let payloads = decoded.suggestions
        else { return [] }

        return payloads.compactMap { payload in
            guard entry.bullets.contains(payload.originalBullet) else { return nil }
            let type = CareerResumeSuggestion.SuggestionType(rawValue: payload.type ?? "") ?? .clarification
            let tier = CareerResumeSuggestion.ConfidenceTier(rawValue: payload.tier ?? "") ?? .verify
            let proposed = payload.proposedBullet ?? ""
            if type == .metricPrompt, proposed.isEmpty {
                return CareerResumeSuggestion(
                    entryHeading: heading,
                    originalBullet: payload.originalBullet,
                    proposedBullet: "",
                    rationale: payload.rationale,
                    type: .metricPrompt,
                    tier: .verify,
                    scoreDeltaEstimate: payload.scoreDeltaEstimate
                )
            }
            guard !proposed.isEmpty, proposed != payload.originalBullet else { return nil }
            return CareerResumeSuggestion(
                entryHeading: heading,
                originalBullet: payload.originalBullet,
                proposedBullet: proposed,
                rationale: payload.rationale,
                type: type,
                tier: tier,
                scoreDeltaEstimate: payload.scoreDeltaEstimate
            )
        }
    }

    private func offlineFallback(
        profile: CareerResumeStructuredProfile,
        missingSkills: [String]
    ) -> [CareerResumeSuggestion] {
        let upgrades: [(String, String)] = [
            ("helped", "Supported"),
            ("assisted", "Contributed to"),
            ("worked on", "Delivered"),
            ("responsible for", "Owned"),
        ]
        var results: [CareerResumeSuggestion] = []
        for entry in profile.experience {
            let heading = entry.headingLines.joined(separator: " · ")
            for bullet in entry.bullets {
                let lower = bullet.lowercased()
                if let (from, to) = upgrades.first(where: { lower.hasPrefix($0.0) }) {
                    let proposed = to + String(bullet.dropFirst(from.count))
                    results.append(CareerResumeSuggestion(
                        entryHeading: heading,
                        originalBullet: bullet,
                        proposedBullet: proposed,
                        rationale: "Stronger action verb for ATS scanability.",
                        type: .actionVerbUpgrade,
                        tier: .safe,
                        scoreDeltaEstimate: 3
                    ))
                } else if !bullet.contains(where: { $0.isNumber }) {
                    results.append(CareerResumeSuggestion(
                        entryHeading: heading,
                        originalBullet: bullet,
                        proposedBullet: "",
                        rationale: "Add a metric (%, $, scale, or team size) if you have one.",
                        type: .metricPrompt,
                        tier: .verify,
                        scoreDeltaEstimate: 5
                    ))
                }
            }
        }
        if let skill = missingSkills.first, let entry = profile.experience.first, let bullet = entry.bullets.first {
            results.append(CareerResumeSuggestion(
                entryHeading: entry.headingLines.joined(separator: " · "),
                originalBullet: bullet,
                proposedBullet: bullet,
                rationale: "Consider honestly connecting adjacent experience to \(skill).",
                type: .keywordInjection,
                tier: .verify,
                scoreDeltaEstimate: 4
            ))
        }
        return results
    }
}
