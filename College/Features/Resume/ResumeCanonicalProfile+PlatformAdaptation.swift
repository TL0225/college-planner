// ResumeCanonicalProfile+PlatformAdaptation.swift
// Feature: Resume
// Purpose: Platform-specific canonical profile transforms using Career ATS guides.

import Foundation
import CollegeCareer

extension ResumeCanonicalProfile {
    /// Applies platform-aware content transforms before export or page-budget checks.
    func adapted(
        for platform: JobBoardPlatform,
        mirrorKeywords: [String] = []
    ) -> ResumeCanonicalProfile {
        var copy = self
        let scoringProfile = CareerATSScoringProfile.profile(for: platform)

        switch platform {
        case .workday:
            copy = copy.inliningTopSkillsIntoExperience(limit: 3)
            copy = copy.expandingCredentialAcronyms()
        case .icims:
            copy = copy.inliningTopSkillsIntoExperience(limit: 2)
        case .oracle:
            copy = copy.expandingCredentialAcronyms()
            copy = copy.reorderingSkillsBeforeEducationWhenPresent()
        default:
            break
        }

        if !mirrorKeywords.isEmpty,
           scoringProfile.keywordMatchMode == .exact || scoringProfile.keywordMatchMode == .stemmed {
            copy = copy.mirroringKeywords(mirrorKeywords)
        }

        _ = CareerATSPortalGuide.tips(for: platform)
        return copy
    }

    var estimatedPlainTextLength: Int {
        var total = 0
        if let summary = basics?.summary { total += summary.count }
        total += skills.joined(separator: " ").count
        total += certifications.joined(separator: " ").count
        for entry in work {
            total += (entry.position ?? "").count
            total += (entry.company ?? "").count
            total += entry.highlights.joined(separator: " ").count
        }
        for entry in education {
            total += (entry.institution ?? "").count
            total += (entry.area ?? "").count
        }
        for entry in projects {
            total += (entry.name ?? "").count
            total += entry.highlights.joined(separator: " ").count
        }
        return total
    }

    func tighteningSummary(maxCharacters: Int) -> ResumeCanonicalProfile {
        guard maxCharacters > 0,
              var basics = basics,
              let summary = basics.summary,
              summary.count > maxCharacters
        else { return self }

        var copy = self
        let trimmed = String(summary.prefix(maxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines)
        basics.summary = trimmed.hasSuffix(".") ? trimmed : trimmed + "…"
        copy.basics = basics
        return copy
    }

    func strippingOptionalSections() -> ResumeCanonicalProfile {
        var copy = self
        copy.projects = []
        copy.certifications = []
        return copy
    }

    func droppingLowestPriorityWorkEntries() -> ResumeCanonicalProfile {
        guard work.count > 1 else { return self }
        var copy = self
        copy.work.removeLast()
        return copy
    }

    // MARK: - Private transforms

    private func inliningTopSkillsIntoExperience(limit: Int) -> ResumeCanonicalProfile {
        guard !skills.isEmpty, !work.isEmpty else { return self }
        var copy = self
        let inlineSkills = skills.prefix(limit).joined(separator: ", ")
        guard var first = copy.work.first else { return self }
        if let lastBullet = first.highlights.last, !lastBullet.localizedCaseInsensitiveContains(inlineSkills) {
            first.highlights.append("Skills: \(inlineSkills)")
        } else if first.highlights.isEmpty {
            first.highlights = ["Skills: \(inlineSkills)"]
        }
        copy.work[0] = first
        return copy
    }

    private func expandingCredentialAcronyms() -> ResumeCanonicalProfile {
        let aliases: [String: String] = [
            "CPA": "Certified Public Accountant",
            "PMP": "Project Management Professional",
            "AWS": "Amazon Web Services",
        ]
        var copy = self
        copy.skills = skills.map { expandedToken($0, aliases: aliases) }
        copy.certifications = certifications.map { expandedToken($0, aliases: aliases) }
        copy.work = work.map { entry in
            var updated = entry
            updated.highlights = entry.highlights.map { expandedToken($0, aliases: aliases) }
            return updated
        }
        return copy
    }

    private func reorderingSkillsBeforeEducationWhenPresent() -> ResumeCanonicalProfile {
        self
    }

    private func mirroringKeywords(_ keywords: [String]) -> ResumeCanonicalProfile {
        guard !keywords.isEmpty, !work.isEmpty else { return self }
        var copy = self
        let existing = Set(
            work.flatMap(\.highlights)
                .joined(separator: " ")
                .lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
        )
        let missing = keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { keyword in
                !existing.contains(keyword.lowercased())
            }
            .prefix(3)
        guard !missing.isEmpty, var first = copy.work.first else { return self }
        first.highlights.append("Relevant: \(missing.joined(separator: ", "))")
        copy.work[0] = first
        return copy
    }

    private func expandedToken(_ value: String, aliases: [String: String]) -> String {
        value
            .split(separator: " ")
            .map { token in
                let key = String(token)
                if let expanded = aliases[key.uppercased()], !value.localizedCaseInsensitiveContains(expanded) {
                    return "\(key) (\(expanded))"
                }
                return key
            }
            .joined(separator: " ")
    }
}

private extension String {
    func localizedCaseInsensitiveContains(_ other: String) -> Bool {
        range(of: other, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
