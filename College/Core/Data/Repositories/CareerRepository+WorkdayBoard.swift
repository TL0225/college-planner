// CareerRepository+WorkdayBoard.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CareerRepository+WorkdayBoard.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData
import CollegeCareer

extension CareerRepository {
    func fetchTrackerForWorkday(companySlug: String, externalId: String) throws -> JobApplication? {
        let slug = companySlug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let external = externalId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slug.isEmpty, !external.isEmpty else { return nil }
        var descriptor = FetchDescriptor<JobApplication>(
            predicate: #Predicate { app in
                app.workdayCompanySlug == slug && app.workdayExternalId == external
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @discardableResult
    func promoteWorkdayPostingToTracker(_ posting: WorkdayJobPosting) throws -> JobApplication {
        let slug = posting.companySlug
        let externalId = posting.externalId

        if let existing = try fetchTrackerForWorkday(companySlug: slug, externalId: externalId) {
            posting.trackedApplication = existing
            existing.workdaySourcePosting = posting
            try saveWorkdayBoard()
            return existing
        }

        let application = JobApplication(
            id: UUID(),
            statusRaw: CareerApplicationStatus.interested.rawValue,
            sortOrder: try nextInterestedSortOrder()
        )
        application.createdAt = Date()
        application.updatedAt = Date()
        application.lastStatusChangeAt = Date()
        application.title = (posting.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        application.company = (posting.companyDisplayName ?? slug).trimmingCharacters(in: .whitespacesAndNewlines)
        application.interviewStatus = ""
        application.postingURLString = posting.applyURLString ?? ""
        application.jobDescriptionText = posting.jobDescriptionText ?? ""
        application.locationText = posting.locationText ?? ""
        application.source = posting.platform ?? JobBoardPlatform.workday.rawValue
        application.workdayExternalId = externalId
        application.workdayCompanySlug = slug
        posting.trackedApplication = application
        application.workdaySourcePosting = posting
        context.insert(application)
        try saveWorkdayBoard()
        CareerSpotlightIndexer.index(application: application)
        return application
    }

    func isPostingTracked(_ posting: WorkdayJobPosting) -> Bool {
        guard let app = posting.trackedApplication else { return false }
        return (try? fetchApplication(id: app.id)) != nil
    }

    func isPostingNew(_ posting: WorkdayJobPosting) -> Bool {
        guard let first = posting.firstSeenAt else { return false }
        guard Date().timeIntervalSince(first) <= WorkdayJobBoardThresholds.newPostingMaxAge else {
            return false
        }
        return !WorkdayOpeningsState.isPostingSeen(
            companySlug: posting.companySlug,
            externalPath: posting.externalPath
        )
    }

    func boardStatus(for posting: WorkdayJobPosting) -> CareerApplicationStatus? {
        guard let app = posting.trackedApplication,
              (try? fetchApplication(id: app.id)) != nil else { return nil }
        return CareerApplicationPresentation.status(for: app)
    }

    func shouldFetchWorkdayDetail(for posting: WorkdayJobPosting, force: Bool) -> Bool {
        if force { return true }
        guard let scraped = posting.detailScrapedAt else { return true }
        return Date().timeIntervalSince(scraped) > WorkdayJobBoardThresholds.detailCacheTTL
    }

    func applyJobBoardDetail(posting: WorkdayJobPosting, detail: ScrapedJobDetail) throws {
        if let loc = detail.locationDisplay { posting.locationText = loc }
        if !detail.descriptionPlain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            posting.jobDescriptionText = detail.descriptionPlain
        }
        if let req = detail.requirementsPlain,
           !req.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            posting.requirementsText = req
        }
        posting.detailScrapedAt = Date()
        posting.lastScrapedAt = Date()
        try saveWorkdayBoard()
    }

    func countNewOpeningsSince(_ date: Date?) throws -> Int {
        let postings = try fetchRecentActivePostings(limit: 500)
        if let date {
            return postings.filter { posting in
                guard posting.isActive, posting.closedAt == nil,
                      let first = posting.firstSeenAt else { return false }
                return first > date
            }.count
        }
        return postings.filter { $0.isActive && $0.closedAt == nil }.count
    }

    func activePostingCount(companySlug: String) throws -> Int {
        try fetchCompanyPostings(companySlug: companySlug).filter(\.isActive).count
    }

    private func nextInterestedSortOrder() throws -> Int32 {
        let interestedRaw = CareerApplicationStatus.interested.rawValue
        let maxOrder = try fetchApplications(limit: 250)
            .filter { $0.statusRaw == interestedRaw }
            .map(\.sortOrder)
            .max() ?? 0
        return maxOrder + 1
    }

    private func saveWorkdayBoard() throws {
        ModelMergeCoalescer.scheduleSave(context)
        ModelMergeCoalescer.flushNow()
        CollegePersistence.shared.bumpCareerRevision()
    }
}