// JobBoardDataAudit.swift
// Feature: Debug
// Purpose: Read-only audit of Openings pipeline data in SwiftData + UserDefaults.

#if DEBUG
import Foundation
import SwiftData

struct JobBoardDataAuditReport: Sendable {
    struct CompanySummary: Sendable {
        let slug: String
        let displayName: String
        let platform: String
        let enabled: Bool
    }

    struct PostingSummary: Sendable {
        let companySlug: String
        let activeCount: Int
        let emptyDescriptionCount: Int
        let neverDetailScrapedCount: Int
    }

    struct ResumeSummary: Sendable {
        let total: Int
        let ingestComplete: Int
        let ingestPending: Int
        let hasStructuredContent: Int
    }

    struct MatchSummary: Sendable {
        let total: Int
        let staleHashCount: Int
        let withoutDetailScrapedCount: Int
    }

    struct TrackerSummary: Sendable {
        let applicationsWithPostingLink: Int
        let brokenPostingLinks: Int
    }

    var companies: [CompanySummary]
    var postings: [PostingSummary]
    var resumes: ResumeSummary
    var matches: MatchSummary
    var tracker: TrackerSummary
    var anomalySamples: [String]
}

enum JobBoardDataAudit {
    @MainActor
    static func run(using persistence: CollegePersistence = .shared) -> JobBoardDataAuditReport {
        let repo = persistence.careerRepository
        let companies = JobBoardCompaniesStore.shared.companies.map {
            JobBoardDataAuditReport.CompanySummary(
                slug: $0.normalizedSlug,
                displayName: $0.displayName,
                platform: $0.platform.rawValue,
                enabled: $0.enabled
            )
        }

        var postingSummaries: [JobBoardDataAuditReport.PostingSummary] = []
        var anomalySamples: [String] = []

        for company in companies {
            let postings = (try? repo.fetchCompanyPostings(companySlug: company.slug)) ?? []
            let active = postings.filter(\.isActive)
            let emptyJD = active.filter {
                ($0.jobDescriptionText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && ($0.requirementsText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            let neverDetail = active.filter { $0.detailScrapedAt == nil }
            postingSummaries.append(
                JobBoardDataAuditReport.PostingSummary(
                    companySlug: company.slug,
                    activeCount: active.count,
                    emptyDescriptionCount: emptyJD.count,
                    neverDetailScrapedCount: neverDetail.count
                )
            )
            for posting in neverDetail.prefix(2) {
                anomalySamples.append("no-detail: \(company.slug) \(posting.externalPath ?? "?")")
            }
        }

        let resumeDocs = VaultReadBridge.careerResumeDocuments(collegePersistence: persistence)
        var ingestComplete = 0
        var ingestPending = 0
        var hasContent = 0
        for doc in resumeDocs {
            let meta = persistence.careerResumeMetadata(for: doc)
            if meta.ingestCompletedAt != nil { ingestComplete += 1 } else { ingestPending += 1 }
            if meta.structuredProfile?.hasContent == true { hasContent += 1 }
            if meta.ingestCompletedAt == nil, meta.targetRole != nil {
                anomalySamples.append("targetRole-before-parse: \(doc.fileName)")
            }
        }

        let matches = (try? repo.fetchAllResumeJobMatches()) ?? []
        var stale = 0
        var withoutDetail = 0
        for match in matches {
            let postings = (try? repo.fetchCompanyPostings(companySlug: match.postingCompanySlug)) ?? []
            let posting = postings.first { $0.externalPath == match.postingExternalPath }
            if let posting {
                if posting.detailScrapedAt == nil { withoutDetail += 1 }
                if posting.descriptionHash != match.descriptionHashAtScore { stale += 1 }
            }
        }

        let applications = (try? repo.fetchApplications(limit: 500)) ?? []
        var linked = 0
        var broken = 0
        for app in applications where app.workdaySourcePosting != nil {
            linked += 1
            if app.workdaySourcePosting?.isActive == false { broken += 1 }
        }

        return JobBoardDataAuditReport(
            companies: companies,
            postings: postingSummaries,
            resumes: .init(
                total: resumeDocs.count,
                ingestComplete: ingestComplete,
                ingestPending: ingestPending,
                hasStructuredContent: hasContent
            ),
            matches: .init(
                total: matches.count,
                staleHashCount: stale,
                withoutDetailScrapedCount: withoutDetail
            ),
            tracker: .init(
                applicationsWithPostingLink: linked,
                brokenPostingLinks: broken
            ),
            anomalySamples: Array(anomalySamples.prefix(25))
        )
    }
}
#endif
