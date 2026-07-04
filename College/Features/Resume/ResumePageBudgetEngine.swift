// ResumePageBudgetEngine.swift
// Feature: Resume
// Purpose: Compile-measure-compress loop for platform export page budgets.

import Foundation
import CollegeCareer

enum ResumePageBudgetCompressionStep: String, Sendable, Equatable {
    case tightenSummary
    case stripOptionalSections
    case dropLowPriorityEntries
}

struct ResumePageBudgetResult: Sendable, Equatable {
    var adaptedProfile: ResumeCanonicalProfile
    var baselinePageCount: Int
    var adaptedPageCount: Int
    var compressionStepsApplied: [ResumePageBudgetCompressionStep]
    var needsUserConfirmation: Bool
    var overflowMessage: String?
    var portalTips: [String]
}

enum ResumePageBudgetEngine {
    private static let linesPerPageEstimate = 52
    private static let charsPerLineEstimate = 80
    private static let defaultSummaryMaxCharacters = 320

    static func estimatePageCount(for profile: ResumeCanonicalProfile) -> Int {
        let textLines = max(1, profile.estimatedPlainTextLength / charsPerLineEstimate)
        let structuralLines = profile.work.count * 3
            + profile.education.count * 2
            + profile.projects.count * 2
            + (profile.skills.isEmpty ? 0 : 2)
            + (profile.certifications.isEmpty ? 0 : 2)
        let totalLines = textLines + structuralLines
        return max(1, Int(ceil(Double(totalLines) / Double(linesPerPageEstimate))))
    }

    static func maxPages(
        for platform: JobBoardPlatform,
        baselinePageCount: Int
    ) -> Int {
        switch platform {
        case .oracle:
            return min(2, baselinePageCount)
        default:
            return baselinePageCount
        }
    }

    static func adaptWithBudget(
        profile: ResumeCanonicalProfile,
        platform: JobBoardPlatform,
        mirrorKeywords: [String] = [],
        baselinePageCount: Int? = nil
    ) -> ResumePageBudgetResult {
        let baseline = baselinePageCount ?? estimatePageCount(for: profile)
        let budget = maxPages(for: platform, baselinePageCount: baseline)
        var adapted = profile.adapted(for: platform, mirrorKeywords: mirrorKeywords)
        var steps: [ResumePageBudgetCompressionStep] = []
        var pageCount = estimatePageCount(for: adapted)

        if pageCount <= budget {
            return ResumePageBudgetResult(
                adaptedProfile: adapted,
                baselinePageCount: baseline,
                adaptedPageCount: pageCount,
                compressionStepsApplied: steps,
                needsUserConfirmation: false,
                overflowMessage: nil,
                portalTips: CareerATSPortalGuide.tips(for: platform)
            )
        }

        let compressedSummary = adapted.tighteningSummary(maxCharacters: defaultSummaryMaxCharacters)
        if compressedSummary != adapted {
            adapted = compressedSummary
            steps.append(.tightenSummary)
            pageCount = estimatePageCount(for: adapted)
        }

        if pageCount > budget {
            let stripped = adapted.strippingOptionalSections()
            if stripped != adapted {
                adapted = stripped
                steps.append(.stripOptionalSections)
                pageCount = estimatePageCount(for: adapted)
            }
        }

        while pageCount > budget, adapted.work.count > 1 {
            adapted = adapted.droppingLowestPriorityWorkEntries()
            if steps.last != .dropLowPriorityEntries {
                steps.append(.dropLowPriorityEntries)
            }
            pageCount = estimatePageCount(for: adapted)
        }

        let scoringProfile = CareerATSScoringProfile.profile(for: platform)
        let needsConfirm = pageCount > budget
        let overflowMessage: String? = needsConfirm
            ? "\(scoringProfile.name) version needs \(String(format: "%.1f", Double(pageCount))) pages — compress summary or remove entries to stay at \(budget) page\(budget == 1 ? "" : "s")."
            : nil

        return ResumePageBudgetResult(
            adaptedProfile: adapted,
            baselinePageCount: baseline,
            adaptedPageCount: pageCount,
            compressionStepsApplied: steps,
            needsUserConfirmation: needsConfirm,
            overflowMessage: overflowMessage,
            portalTips: CareerATSPortalGuide.tips(for: platform)
        )
    }
}
