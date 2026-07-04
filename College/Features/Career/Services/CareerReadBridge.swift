// CareerReadBridge.swift
// Feature: Career
// Purpose: Career module — CareerApplicationStatsRow.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData
import CollegeCareer

/// Vault-backed resume presence for FTUE, profile CTAs, and match eligibility.
struct ResumeAvailability: Sendable, Equatable {
    enum State: Sendable, Equatable {
        case none
        case draftOnly
        case uploadedAwaitingParse
        case ready(documentID: UUID)
        case lowParserHealth(documentID: UUID, percent: Int)
    }

    var state: State
    var primaryDocumentID: UUID?
    var draftDocumentID: UUID?
    var resumeCount: Int
    var activeResumeCount: Int
}

/// Row used for career stats charts (local store-only).
struct CareerApplicationStatsRow: Sendable {
    let status: CareerApplicationStatus
    let company: String
    let lastStatusChangeAt: Date?
    let createdAt: Date?
}

/// local store-only career reads (Phase 7f).
@MainActor
enum CareerReadBridge {
    static func pipelineMetrics() -> CollegePersistence.CareerPipelineMetrics {
        let repo = CareerRepository(context: AppDataStore.shared.profileContext)
        return (try? repo.pipelineMetrics()) ?? .zero
    }

    static func statusCounts() -> [CareerApplicationStatus: Int]? {
        let repo = CareerRepository(context: AppDataStore.shared.profileContext)
        return try? repo.statusCounts()
    }

    static func careerApplications() -> [JobApplication] {
        let repo = CareerRepository(context: AppDataStore.shared.profileContext)
        return (try? repo.fetchApplications(limit: 250)) ?? []
    }

    static func careerResumeDocuments(
        collegePersistence: CollegePersistence = .shared
    ) -> [VaultDocument] {
        VaultReadBridge.careerResumeDocuments(collegePersistence: collegePersistence)
    }

    static func hasCareerResume(
        collegePersistence: CollegePersistence = .shared
    ) -> Bool {
        resumeAvailability(collegePersistence: collegePersistence).activeResumeCount > 0
    }

    static func resumeAvailability(
        collegePersistence: CollegePersistence = .shared
    ) -> ResumeAvailability {
        let documents = careerResumeDocuments(collegePersistence: collegePersistence)
        let activeDocuments = documents.filter {
            !collegePersistence.careerResumeMetadata(for: $0).archived
        }
        let mapped = activeDocuments.map {
            (documentID: $0.id, metadata: collegePersistence.careerResumeMetadata(for: $0))
        }

        guard !mapped.isEmpty else {
            return ResumeAvailability(
                state: .none,
                primaryDocumentID: nil,
                draftDocumentID: nil,
                resumeCount: documents.count,
                activeResumeCount: 0
            )
        }

        if let draft = mapped.first(where: isBuilderDraft(in:)) {
            let hasReady = mapped.contains { isReadyResume(in: $0.metadata) }
            if !hasReady {
                return ResumeAvailability(
                    state: .draftOnly,
                    primaryDocumentID: nil,
                    draftDocumentID: draft.documentID,
                    resumeCount: documents.count,
                    activeResumeCount: activeDocuments.count
                )
            }
        }

        if let picked = JobBoardMatchEligibility.pickPrimaryResume(documents: mapped) {
            if JobBoardMatchEligibility.resumeContext(
                from: picked.metadata,
                documentID: picked.documentID
            ) != nil {
                if let health = picked.metadata.parserHealthPercent,
                   health < CareerResumeLibraryTheme.parserHealthGreenMinimum {
                    return ResumeAvailability(
                        state: .lowParserHealth(documentID: picked.documentID, percent: health),
                        primaryDocumentID: picked.documentID,
                        draftDocumentID: nil,
                        resumeCount: documents.count,
                        activeResumeCount: activeDocuments.count
                    )
                }
                return ResumeAvailability(
                    state: .ready(documentID: picked.documentID),
                    primaryDocumentID: picked.documentID,
                    draftDocumentID: nil,
                    resumeCount: documents.count,
                    activeResumeCount: activeDocuments.count
                )
            }

            if JobBoardMatchEligibility.hasPendingResumeParse(in: picked.metadata) {
                return ResumeAvailability(
                    state: .uploadedAwaitingParse,
                    primaryDocumentID: picked.documentID,
                    draftDocumentID: nil,
                    resumeCount: documents.count,
                    activeResumeCount: activeDocuments.count
                )
            }
        }

        if mapped.contains(where: { JobBoardMatchEligibility.hasPendingResumeParse(in: $0.metadata) }) {
            return ResumeAvailability(
                state: .uploadedAwaitingParse,
                primaryDocumentID: mapped.first?.documentID,
                draftDocumentID: nil,
                resumeCount: documents.count,
                activeResumeCount: activeDocuments.count
            )
        }

        return ResumeAvailability(
            state: .none,
            primaryDocumentID: nil,
            draftDocumentID: nil,
            resumeCount: documents.count,
            activeResumeCount: activeDocuments.count
        )
    }

    private static func isBuilderDraft(in item: (documentID: UUID, metadata: CareerResumeMetadataV1)) -> Bool {
        let meta = item.metadata
        return meta.documentJSON != nil
            && meta.ingestCompletedAt == nil
            && meta.canonicalProfileJSON != nil
    }

    private static func isReadyResume(in metadata: CareerResumeMetadataV1) -> Bool {
        metadata.ingestCompletedAt != nil
            || ResumeCanonicalProfile.decode(from: metadata.canonicalProfileJSON)?.hasContent == true
    }

    static func applicationStatsRows() -> [CareerApplicationStatsRow] {
        careerApplications().map { application in
            CareerApplicationStatsRow(
                status: CareerApplicationPresentation.status(for: application),
                company: (application.company ?? "Unknown").trimmingCharacters(in: .whitespaces),
                lastStatusChangeAt: application.lastStatusChangeAt,
                createdAt: application.createdAt
            )
        }
    }

    static func pipelineCountsForCharts(
        from rows: [CareerApplicationStatsRow]
    ) -> [(status: CareerApplicationStatus, count: Int)] {
        CareerApplicationStatus.allCases.map { status in
            let count = rows.filter { $0.status == status }.count
            return (status, count)
        }.filter { $0.count > 0 }
    }

    static func weeklyApplications(
        from rows: [CareerApplicationStatsRow],
        weekCount: Int = 8
    ) -> [(week: Date, count: Int)] {
        let cal = Calendar.current
        let now = Date()
        return (0..<weekCount).reversed().compactMap { offset -> (Date, Int)? in
            guard let weekStart = cal.date(byAdding: .weekOfYear, value: -offset, to: now),
                  let interval = cal.dateInterval(of: .weekOfYear, for: weekStart)
            else { return nil }
            let count = rows.filter { row in
                guard let applied = row.lastStatusChangeAt ?? row.createdAt else { return false }
                return interval.contains(applied) && row.status != .interested
            }.count
            return (interval.start, count)
        }
    }

    static func companyResponseRates(
        from rows: [CareerApplicationStatsRow],
        limit: Int = 12
    ) -> [(company: String, applied: Int, advanced: Int)] {
        let grouped = Dictionary(grouping: rows) {
            $0.company.trimmingCharacters(in: .whitespaces)
        }
        return grouped.map { company, apps in
            let applied = apps.filter { $0.status != .interested }.count
            let advanced = apps.filter {
                $0.status == .interviewing || $0.status == .offer || $0.status == .accepted
            }.count
            return (company, applied, advanced)
        }
        .filter { $0.applied > 0 }
        .sorted { $0.applied > $1.applied }
        .prefix(limit)
        .map { $0 }
    }
}
