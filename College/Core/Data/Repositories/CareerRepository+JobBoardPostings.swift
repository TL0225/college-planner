// CareerRepository+JobBoardPostings.swift
// Feature: Core/Data
// Purpose: Fetch and delete mirrored job-board postings in SwiftData.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension CareerRepository {
    private static let companyPostingsFetchLimit = 2000

    func hasMirroredJobBoardPostingRows() throws -> Bool {
        var descriptor = FetchDescriptor<JobBoardPosting>()
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
    }

    func fetchJobBoardPosting(id: UUID) throws -> JobBoardPosting? {
        var descriptor = FetchDescriptor<JobBoardPosting>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchCompanyPostings(companySlug: String, limit: Int = companyPostingsFetchLimit) throws -> [JobBoardPosting] {
        let slug = companySlug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !slug.isEmpty else { return [] }
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
        descriptor.fetchLimit = max(1, limit)
        return try context.fetch(descriptor)
    }

    func fetchCompanyPostingListDTOs(
        companySlug: String,
        limit: Int = companyPostingsFetchLimit
    ) throws -> [JobBoardPostingListDTO] {
        try fetchCompanyPostings(companySlug: companySlug, limit: limit).map(JobBoardPostingListDTO.init(posting:))
    }

    func fetchPosting(companySlug: String, externalPath: String) throws -> JobBoardPosting? {
        let slug = companySlug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let path = externalPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slug.isEmpty, !path.isEmpty else { return nil }
        var descriptor = FetchDescriptor<JobBoardPosting>(
            predicate: #Predicate { posting in
                posting.companySlug == slug && posting.externalPath == path
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchRecentActivePostings(limit: Int = 5) throws -> [JobBoardPosting] {
        var descriptor = FetchDescriptor<JobBoardPosting>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\.firstSeenAt, order: .reverse)]
        )
        descriptor.fetchLimit = max(1, limit)
        return try context.fetch(descriptor)
    }

    func fetchPostings(companySlugs: [String], limitPerCompany: Int = companyPostingsFetchLimit) throws -> [JobBoardPosting] {
        let slugs = Set(
            companySlugs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        guard !slugs.isEmpty else { return [] }
        var combined: [JobBoardPosting] = []
        for slug in slugs.sorted() {
            let batch = try fetchCompanyPostings(companySlug: slug, limit: limitPerCompany)
            combined.append(contentsOf: batch)
        }
        return combined
    }

    func deleteJobBoardPosting(id: UUID) throws {
        guard let posting = try fetchJobBoardPosting(id: id) else { return }
        context.delete(posting)
        ModelMergeCoalescer.scheduleSave(context)
    }

    /// Deletes every mirrored posting (active or inactive) for a company slug.
    /// Returns the number of rows removed.
    @discardableResult
    func deleteJobBoardPostings(companySlug: String) throws -> Int {
        let slug = companySlug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !slug.isEmpty else { return 0 }
        let descriptor = FetchDescriptor<JobBoardPosting>(
            predicate: #Predicate { $0.companySlug == slug }
        )
        let postings = try context.fetch(descriptor)
        guard !postings.isEmpty else { return 0 }
        for posting in postings {
            context.delete(posting)
        }
        ModelMergeCoalescer.scheduleSave(context)
        return postings.count
    }
}