// CollegePersistence+Career.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CollegePersistence+Career.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData
import CollegeCareer

extension CollegePersistence {
    typealias CareerPipelineMetrics = CareerRepository.CareerPipelineMetrics
    typealias CareerNetworkingKPIs = CareerRepository.CareerNetworkingKPIs
    typealias CareerResumeLibraryStats = CareerRepository.CareerResumeLibraryStats

    private var careerRepo: CareerRepository { careerRepository }

    @discardableResult
    func addCareerApplication(
        title: String,
        company: String,
        postingURLString: String,
        jobDescriptionText: String,
        interviewStatus: String,
        applicationDeadline: Date?,
        status: CareerApplicationStatus,
        source: String = "manual",
        sourceRequestId: UUID? = nil,
        extractedKeywordsJSON: String? = nil,
        locationText: String? = nil,
        baseSalaryText: String? = nil
    ) throws -> JobApplication {
        try careerRepo.addApplication(
            title: title,
            company: company,
            postingURLString: postingURLString,
            jobDescriptionText: jobDescriptionText,
            interviewStatus: interviewStatus,
            applicationDeadline: applicationDeadline,
            status: status,
            source: source,
            sourceRequestId: sourceRequestId,
            extractedKeywordsJSON: extractedKeywordsJSON,
            locationText: locationText,
            baseSalaryText: baseSalaryText
        )
    }

    func moveCareerApplication(id: UUID, to status: CareerApplicationStatus) {
        try? careerRepo.moveApplication(id: id, to: status)
    }

    func deleteCareerApplication(_ app: JobApplication) {
        try? careerRepo.deleteApplication(app)
    }

    func deleteCareerApplication(id: UUID) {
        guard let app = try? careerRepo.fetchApplication(id: id) else { return }
        try? careerRepo.deleteApplication(app)
    }

    func upsertCareerApplication(from saveRequest: CareerSaveRequest) {
        try? careerRepo.upsertApplication(from: saveRequest)
    }

    @discardableResult
    func quickAddCareerInterested(companyName: String) -> JobApplication {
        (try? careerRepo.quickAddInterested(companyName: companyName))
            ?? JobApplication(statusRaw: CareerApplicationStatus.interested.rawValue)
    }

    func careerPipelineMetrics() -> CareerPipelineMetrics {
        (try? careerRepo.pipelineMetrics()) ?? .zero
    }

    func careerNetworkingKPIs() -> CareerNetworkingKPIs {
        (try? careerRepo.networkingKPIs()) ?? .zero
    }

    func careerPriority(for application: JobApplication) -> CareerKanbanTheme.Priority {
        careerRepo.priority(for: application)
    }

    func setCareerPriority(_ priority: CareerKanbanTheme.Priority, for application: JobApplication) {
        try? careerRepo.setPriority(priority, for: application)
    }

    func careerNetworkingNotes(for application: JobApplication) -> String {
        careerRepo.networkingNotes(for: application)
    }

    func setCareerNetworkingNotes(_ notes: String, for application: JobApplication) {
        try? careerRepo.setNetworkingNotes(notes, for: application)
    }

    func careerOfferCompensationPackage(for application: JobApplication) -> CareerOfferCompensationPackage {
        careerRepo.offerCompensationPackage(for: application)
    }

    func setCareerOfferCompensationPackage(
        _ package: CareerOfferCompensationPackage,
        for application: JobApplication
    ) {
        try? careerRepo.setOfferCompensationPackage(package, for: application)
    }

    func markCareerFollowUpComplete(for app: JobApplication) {
        try? careerRepo.markFollowUpComplete(for: app)
    }

    func snoozeCareerFollowUp(for app: JobApplication, days: Int = 3) {
        try? careerRepo.snoozeFollowUp(for: app, days: days)
    }

    func jobApplication(id: UUID) -> JobApplication? {
        try? careerRepo.fetchApplication(id: id)
    }

    func recruiterContact(id: UUID) -> RecruiterContact? {
        try? careerRepo.fetchRecruiterContact(id: id)
    }

    func importJobBoardListings(
        company: JobBoardCompany,
        listings: [ScrapedJobListing]
    ) throws -> Int {
        try careerRepo.applyJobBoardListings(company: company, listings: listings)
    }

    func beginJobBoardListImport(company: JobBoardCompany) {
        let slug = company.normalizedSlug
        jobBoardListImportSessionStates[slug] = JobBoardListImportSessionState(company: company)
    }

    func mergeJobBoardListImportPage(companySlug: String, listings: [ScrapedJobListing]) async throws {
        guard var state = jobBoardListImportSessionStates[companySlug], !state.finalized else { return }
        let company = state.company
        let container = appDataStore.profileContainer
        let seenPaths = state.seenPaths
        let updatedPaths = try await BackgroundServiceExecutor.persistOffMain(container: container) { ctx in
            var paths = seenPaths
            _ = try JobBoardListImportWriter.mergePage(
                context: ctx,
                company: company,
                listings: listings,
                seenPaths: &paths
            )
            try ctx.save()
            return paths
        }
        state.seenPaths = updatedPaths
        jobBoardListImportSessionStates[companySlug] = state
    }

    func discardJobBoardListImport(companySlug: String) {
        jobBoardListImportSessionStates.removeValue(forKey: companySlug)
    }

    func jobBoardListImportHasMergedPages(companySlug: String) -> Bool {
        guard let state = jobBoardListImportSessionStates[companySlug] else { return false }
        return !state.seenPaths.isEmpty
    }

    func finalizeJobBoardListImport(companySlug: String) async throws -> Int {
        guard let state = jobBoardListImportSessionStates.removeValue(forKey: companySlug),
              !state.finalized else { return 0 }
        let company = state.company
        let container = appDataStore.profileContainer
        let count = try await BackgroundServiceExecutor.persistOffMain(container: container) { ctx in
            let n = try JobBoardListImportWriter.finalizeRemovals(
                context: ctx,
                company: company,
                seenPaths: state.seenPaths
            )
            try ctx.save()
            return n
        }
        bumpCareerRevision()
        return count
    }

    func touchActiveJobBoardPostings(companySlug: String) {
        try? careerRepo.touchActiveJobBoardPostings(companySlug: companySlug)
    }

    func countNewOpeningsSince(_ date: Date?) -> Int {
        (try? careerRepo.countNewOpeningsSince(date)) ?? 0
    }

    /// Removes all mirrored job-board postings for a company slug.
    /// Returns the number of rows removed.
    @discardableResult
    func clearJobBoardPostings(companySlug: String) -> Int {
        (try? careerRepo.deleteJobBoardPostings(companySlug: companySlug)) ?? 0
    }

    func newOpeningsCount(companySlug: String) -> Int {
        JobBoardOpeningsState.newCountForCompany(slug: companySlug)
    }

    func isPostingTracked(_ posting: JobBoardPosting) -> Bool {
        careerRepo.isPostingTracked(posting)
    }

    func isPostingNew(_ posting: JobBoardPosting) -> Bool {
        careerRepo.isPostingNew(posting)
    }

    func boardStatus(for posting: JobBoardPosting) -> CareerApplicationStatus? {
        careerRepo.boardStatus(for: posting)
    }

    func shouldFetchJobBoardDetail(for posting: JobBoardPosting, force: Bool) -> Bool {
        careerRepo.shouldFetchJobBoardDetail(for: posting, force: force)
    }

    @discardableResult
    func promoteJobBoardPostingToTracker(
        _ posting: JobBoardPosting,
        recommendedResumeID: UUID? = nil
    ) -> JobApplication {
        (try? careerRepo.promoteJobBoardPostingToTracker(posting, recommendedResumeID: recommendedResumeID))
            ?? JobApplication(statusRaw: CareerApplicationStatus.interested.rawValue)
    }

    func applyJobBoardDetail(posting: JobBoardPosting, detail: ScrapedJobDetail) {
        try? careerRepo.applyJobBoardDetail(posting: posting, detail: detail)
    }

    func careerResumeMetadata(for document: VaultDocument) -> CareerResumeMetadataV1 {
        careerRepo.careerResumeMetadata(for: document)
    }

    func setCareerResumeMetadata(_ meta: CareerResumeMetadataV1, for document: VaultDocument) throws {
        try careerRepo.setCareerResumeMetadata(meta, for: document)
        bumpVaultRevision()
        bumpCareerRevision()
    }

    func setCareerResumeFavorite(_ favorite: Bool, for document: VaultDocument) {
        try? careerRepo.setCareerResumeFavorite(favorite, for: document)
        bumpVaultRevision()
    }

    func careerResumeLibraryStats(for documents: [VaultDocument]) -> CareerResumeLibraryStats {
        careerRepo.careerResumeLibraryStats(for: documents)
    }

    func scoreCareerResumeHeuristic(for document: VaultDocument) async -> Int {
        await careerRepo.scoreCareerResumeHeuristic(for: document, vaultRepository: vaultRepository)
    }

    func persistCareerResumeATSScore(_ score: Int, for document: VaultDocument) {
        try? careerRepo.persistCareerResumeATSScore(score, for: document)
        bumpVaultRevision()
    }

    func careerResumeUsageCount(for resume: VaultDocument) -> Int {
        careerRepo.careerResumeUsageCount(for: resume)
    }

    @discardableResult
    func ensureCareerResumesVaultFolder() -> UUID? {
        try? careerRepo.ensureCareerResumesVaultFolder(vaultRepository: vaultRepository)
    }

    @discardableResult
    func importCareerResume(from url: URL, initialMetadata: CareerResumeMetadataV1? = nil) async throws -> VaultDocument? {
        let doc = try await careerRepo.importCareerResume(from: url, vaultRepository: vaultRepository)
        fetchVaultDocuments()
        bumpVaultRevision()
        if let doc {
            if let initialMetadata {
                try setCareerResumeMetadata(initialMetadata, for: doc)
            }
            let documentID = doc.id
            Task {
                await CareerResumeIngestService.shared.ingest(documentID: documentID)
            }
        }
        return doc
    }

    func scheduleCareerResumeIngest(documentID: UUID) {
        Task {
            await CareerResumeIngestService.shared.ingest(documentID: documentID)
        }
    }

    func careerResumeBaselineText() -> String {
        careerRepo.careerResumeBaselineText()
    }

    func prefetchCareerApplicationsForLaunch() async -> Int {
        await Task.yield()
        return (try? careerRepo.fetchApplications(limit: 250).count) ?? 0
    }
}