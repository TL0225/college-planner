// JobBoardReadBridge.swift
// Feature: Career
// Purpose: Career module — JobBoardReadBridge.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

private let jobBoardCompanyPostingsFetchLimit = 2000

/// Local store-only job-board reads (Phase 7f).
@MainActor
enum JobBoardReadBridge {
    static func companyPostings(companySlug: String) -> [JobBoardPosting] {
        let repo = AppDataStore.shared.careerRepository
        return (try? repo.fetchCompanyPostings(companySlug: companySlug)) ?? []
    }

    /// Background fetch so large boards don't block the main thread (e.g. after resume from background).
    static func companyPostingsOffMain(companySlug: String) async -> [JobBoardPosting] {
        let dtos = await companyPostingListDTOsOffMain(companySlug: companySlug)
        let repo = AppDataStore.shared.careerRepository
        return dtos.compactMap { dto in
            repo.context.model(for: dto.persistentModelID) as? JobBoardPosting
        }
    }

    /// Maps list scalars on a read context so the main actor only faults by persistent ID.
    static func companyPostingListDTOsOffMain(companySlug: String) async -> [JobBoardPostingListDTO] {
        let container = AppDataStore.shared.profileContainer
        let slug = companySlug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let fetchLimit = jobBoardCompanyPostingsFetchLimit
        return await Task.detached(priority: .userInitiated) {
            let context = BackgroundModelContextPolicy.makeReadContext(container: container)
            var descriptor = FetchDescriptor<JobBoardPosting>(
                predicate: #Predicate { posting in
                    posting.isActive && posting.companySlug == slug
                },
                sortBy: [
                    SortDescriptor(\.postedAt, order: .reverse),
                    SortDescriptor(\.firstSeenAt, order: .reverse),
                    SortDescriptor(\.title, order: .forward),
                ]
            )
            descriptor.fetchLimit = fetchLimit
            guard let postings = try? context.fetch(descriptor) else { return [] }
            return postings.map(JobBoardPostingListDTO.init(posting:))
        }.value
    }

    static func recentActivePostings(limit: Int = 5) -> [JobBoardPosting] {
        let repo = AppDataStore.shared.careerRepository
        return (try? repo.fetchRecentActivePostings(limit: limit)) ?? []
    }

    static func posting(companySlug: String, externalPath: String) -> JobBoardPosting? {
        let repo = AppDataStore.shared.careerRepository
        return try? repo.fetchPosting(companySlug: companySlug, externalPath: externalPath)
    }

    static func postings(companySlugs: [String]) -> [JobBoardPosting] {
        let repo = AppDataStore.shared.careerRepository
        return (try? repo.fetchPostings(companySlugs: companySlugs)) ?? []
    }

    /// Off-main multi-company read used by unified smart boards.
    static func postingsOffMain(companySlugs: [String]) async -> [JobBoardPosting] {
        let slugs = companySlugs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard !slugs.isEmpty else { return [] }
        var combined: [JobBoardPosting] = []
        combined.reserveCapacity(slugs.count * 64)
        for slug in slugs.sorted() {
            let batch = await companyPostingsOffMain(companySlug: slug)
            combined.append(contentsOf: batch)
        }
        return combined
    }
}
