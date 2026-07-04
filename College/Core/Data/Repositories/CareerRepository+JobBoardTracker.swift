// CareerRepository+JobBoardTracker.swift
// Feature: Core/Data
// Purpose: Promote postings to the career tracker and apply scraped detail payloads.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData
import CollegeCareer

extension CareerRepository {
    func fetchTrackerForJobBoardPosting(companySlug: String, externalId: String) throws -> JobApplication? {
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
    func promoteJobBoardPostingToTracker(
        _ posting: JobBoardPosting,
        recommendedResumeID: UUID? = nil
    ) throws -> JobApplication {
        let slug = posting.companySlug
        let externalId = posting.externalId

        if let existing = try fetchTrackerForJobBoardPosting(companySlug: slug, externalId: externalId) {
            posting.trackedApplication = existing
            existing.workdaySourcePosting = posting
            try attachRecommendedResume(recommendedResumeID, to: existing, posting: posting)
            try saveJobBoardChanges()
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
        try attachRecommendedResume(recommendedResumeID, to: application, posting: posting)
        try saveJobBoardChanges()
        CareerSpotlightIndexer.index(application: application)
        return application
    }

    private func attachRecommendedResume(
        _ resumeID: UUID?,
        to application: JobApplication,
        posting: JobBoardPosting
    ) throws {
        guard let resumeID,
              let resume = try VaultRepository(context: context).fetchDocument(id: resumeID) else { return }

        application.submittedResume = resume
        application.resumeDisplayName = resume.customDisplayName ?? resume.fileName

        let postingMatch: CareerResumeJobMatch? = {
            if let path = posting.externalPath {
                return try? fetchResumeJobMatch(
                    companySlug: posting.companySlug,
                    externalPath: path,
                    resumeDocumentID: resumeID
                )
            }
            return nil
        }()
        let manualMatch = try? fetchResumeJobMatch(
            companySlug: CareerResumeJobMatchKey.companySlug(for: application),
            externalPath: CareerResumeJobMatchKey.manualApplicationExternalPath(application.id),
            resumeDocumentID: resumeID
        )
        if let match = postingMatch ?? manualMatch {
            application.matchScoreAtSubmission = match.overallScore
            application.matchResultJSONAtSubmission = match.resultJSON
            application.submittedResumeContentHash = match.resumeHashAtScore
        } else {
            let meta = careerResumeMetadata(for: resume)
            application.submittedResumeContentHash = meta.parsedTextHash
        }
    }

    func isPostingTracked(_ posting: JobBoardPosting) -> Bool {
        guard let app = posting.trackedApplication else { return false }
        return (try? fetchApplication(id: app.id)) != nil
    }

    func isPostingNew(_ posting: JobBoardPosting) -> Bool {
        guard let first = posting.firstSeenAt else { return false }
        guard Date().timeIntervalSince(first) <= JobBoardThresholds.newPostingMaxAge else {
            return false
        }
        return !JobBoardOpeningsState.isPostingSeen(
            companySlug: posting.companySlug,
            externalPath: posting.externalPath
        )
    }

    func boardStatus(for posting: JobBoardPosting) -> CareerApplicationStatus? {
        guard let app = posting.trackedApplication,
              (try? fetchApplication(id: app.id)) != nil else { return nil }
        return CareerApplicationPresentation.status(for: app)
    }

    func shouldFetchJobBoardDetail(for posting: JobBoardPosting, force: Bool) -> Bool {
        if force { return true }
        guard let scraped = posting.detailScrapedAt else { return true }
        return Date().timeIntervalSince(scraped) > JobBoardThresholds.detailCacheTTL
    }

    func applyJobBoardDetail(posting: JobBoardPosting, detail: ScrapedJobDetail) throws {
        if let loc = detail.locationDisplay { posting.locationText = loc }
        if !detail.descriptionPlain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            posting.jobDescriptionText = detail.descriptionPlain
        }
        if let req = detail.requirementsPlain,
           !req.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            posting.requirementsText = req
        }
        if let newHash = JobBoardMatchEligibility.postingContentHash(
            jobDescriptionText: posting.jobDescriptionText,
            requirementsText: posting.requirementsText
        ) {
            if posting.descriptionHash != newHash {
                posting.descriptionHash = newHash
                if let path = posting.externalPath {
                    try invalidateResumeJobMatches(
                        companySlug: posting.companySlug,
                        externalPath: path,
                        descriptionHash: newHash
                    )
                }
            }
        }
        posting.detailScrapedAt = Date()
        posting.lastScrapedAt = Date()
        try saveJobBoardChanges()
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

    struct PostingLocationEntry: Sendable {
        let companyName: String
        let locationText: String
    }

    func distinctPostingLocations(companySlug: String) throws -> [String] {
        let texts = try fetchCompanyPostings(companySlug: companySlug)
            .filter(\.isActive)
            .compactMap(\.locationText)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(Set(texts))
    }

    func distinctAllPostingLocations(limit: Int = 200) throws -> [PostingLocationEntry] {
        let postings = try fetchRecentActivePostings(limit: limit)
        var seen = Set<String>()
        var output: [PostingLocationEntry] = []
        for posting in postings where posting.isActive {
            guard let location = posting.locationText?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !location.isEmpty else { continue }
            let company = (posting.companyDisplayName ?? posting.companySlug).trimmingCharacters(in: .whitespacesAndNewlines)
            let key = "\(company.lowercased())|\(location.lowercased())"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            output.append(PostingLocationEntry(companyName: company, locationText: location))
        }
        return output
    }

    private func nextInterestedSortOrder() throws -> Int32 {
        let interestedRaw = CareerApplicationStatus.interested.rawValue
        let maxOrder = try fetchApplications(limit: 250)
            .filter { $0.statusRaw == interestedRaw }
            .map(\.sortOrder)
            .max() ?? 0
        return maxOrder + 1
    }

    private func saveJobBoardChanges() throws {
        ModelMergeCoalescer.scheduleSave(context)
        ModelMergeCoalescer.flushNow()
        CollegePersistence.shared.bumpCareerRevision()
    }
}