// JobBoardResumeMatchController.swift
// Feature: Career / Job Board
// Purpose: Observable match state for job detail and apply attachment flows.

import Foundation
import Observation
import CollegeCareer

@Observable
@MainActor
final class JobBoardResumeMatchController {
    private(set) var matchRows: [CareerResumeMatchRow] = []
    private(set) var isScoringResumes = false
    private(set) var usedPartialFallback = false
    private(set) var primaryResumeContext: JobBoardResumeMatchContext?
    private(set) var hasPendingResumeParse = false

    private var scoringTask: Task<Void, Never>?
    private let collegePersistence: CollegePersistence

    init(collegePersistence: CollegePersistence) {
        self.collegePersistence = collegePersistence
    }

    var recommendedRow: CareerResumeMatchRow? {
        matchRows.first(where: \.isRecommended) ?? matchRows.first
    }

    /// Rows for resume attachment UI — scored matches when available.
    var attachmentRows: [CareerResumeMatchRow] {
        if !matchRows.isEmpty { return matchRows }
        guard let fallback = resolvedResumeForApply() else { return [] }
        return [
            CareerResumeMatchRow(
                resumeDocumentID: fallback.id,
                displayName: fallback.name,
                overallScore: 0,
                keywordScore: 0,
                semanticScore: 0,
                experienceScore: 0,
                matchingSkills: [],
                missingKeywords: [],
                tip: "",
                isRecommended: true
            ),
        ]
    }

    func detailMatchState(for posting: JobBoardPosting) -> JobBoardDetailMatchState {
        JobBoardMatchEligibility.detailMatchState(
            hasParsedResume: primaryResumeContext != nil,
            hasPendingParse: hasPendingResumeParse,
            hasUsableJD: JobBoardMatchEligibility.hasUsableJobDescription(posting),
            isScoring: isScoringResumes,
            hasScoredRows: !matchRows.isEmpty
        )
    }

    func reset(for posting: JobBoardPosting) {
        scoringTask?.cancel()
        reloadCachedMatchRows(for: posting)
        isScoringResumes = false
        usedPartialFallback = false
        reloadResumeContext()
    }

    func cancelScoring() {
        scoringTask?.cancel()
    }

    func reloadResumeContext() {
        let docs = VaultReadBridge.careerResumeDocuments(collegePersistence: collegePersistence)
            .filter { !collegePersistence.careerResumeMetadata(for: $0).archived }
            .map { (documentID: $0.id, metadata: collegePersistence.careerResumeMetadata(for: $0)) }
        guard let picked = JobBoardMatchEligibility.pickPrimaryResume(documents: docs) else {
            primaryResumeContext = nil
            hasPendingResumeParse = false
            return
        }
        primaryResumeContext = JobBoardMatchEligibility.resumeContext(
            from: picked.metadata,
            documentID: picked.documentID
        )
        hasPendingResumeParse = JobBoardMatchEligibility.hasPendingResumeParse(in: picked.metadata)
            && primaryResumeContext == nil
    }

    func reloadCachedMatchRows(for posting: JobBoardPosting) {
        matchRows = JobBoardMatchEligibility.cachedMatchRows(
            for: posting,
            collegePersistence: collegePersistence
        )
    }

    func ensureMatchScoresIfNeeded(for posting: JobBoardPosting, company: JobBoardCompany) {
        guard matchRows.isEmpty else { return }
        guard JobBoardMatchEligibility.hasUsableJobDescription(posting) else { return }
        scheduleResumeScoring(for: posting, company: company, debounce: false)
    }

    func scheduleResumeScoring(
        for posting: JobBoardPosting,
        company: JobBoardCompany,
        debounce: Bool,
        isLoadingDetail: Bool = false
    ) {
        guard JobBoardMatchEligibility.hasUsableJobDescription(posting) else {
            scoringTask?.cancel()
            matchRows = []
            isScoringResumes = isLoadingDetail
            return
        }

        scoringTask?.cancel()
        scoringTask = Task {
            if debounce {
                try? await Task.sleep(for: .milliseconds(400))
            }
            guard !Task.isCancelled else { return }
            isScoringResumes = true
            let postingSnapshot = CareerATSPostingSnapshot(posting: posting)
            let bundle = await CareerATSService.shared.scoreAllResumes(
                posting: postingSnapshot,
                platform: company.platform,
                priority: .userInitiated
            )
            guard !Task.isCancelled else { return }
            matchRows = bundle.rows
            usedPartialFallback = bundle.usedPartialFallback
            isScoringResumes = false
        }
    }

    func resolvedResumeForApply() -> (id: UUID, name: String)? {
        if let row = recommendedRow {
            return (row.resumeDocumentID, row.displayName)
        }
        if let ctx = primaryResumeContext,
           let document = try? collegePersistence.vaultRepository.fetchDocument(id: ctx.documentID) {
            let name = document.customDisplayName ?? document.fileName
            return (ctx.documentID, name)
        }
        let docs = VaultReadBridge.careerResumeDocuments(collegePersistence: collegePersistence)
            .filter { !collegePersistence.careerResumeMetadata(for: $0).archived }
        guard let document = docs.first else { return nil }
        return (document.id, document.customDisplayName ?? document.fileName)
    }
}
