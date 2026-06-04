// CareerRepository+Workday.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CareerRepository+Workday.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension CareerRepository {
    private static let companyPostingsFetchLimit = 2000

    func hasMirroredWorkdayPostingRows() throws -> Bool {
        var descriptor = FetchDescriptor<WorkdayJobPosting>()
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
    }

    func fetchWorkdayPosting(id: UUID) throws -> WorkdayJobPosting? {
        var descriptor = FetchDescriptor<WorkdayJobPosting>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchCompanyPostings(companySlug: String, limit: Int = companyPostingsFetchLimit) throws -> [WorkdayJobPosting] {
        let slug = companySlug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !slug.isEmpty else { return [] }
        var descriptor = FetchDescriptor<WorkdayJobPosting>(
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

    func fetchPosting(companySlug: String, externalPath: String) throws -> WorkdayJobPosting? {
        let slug = companySlug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let path = externalPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slug.isEmpty, !path.isEmpty else { return nil }
        return try fetchCompanyPostings(companySlug: slug, limit: Self.companyPostingsFetchLimit)
            .first { ($0.externalPath ?? "") == path }
    }

    func fetchRecentActivePostings(limit: Int = 5) throws -> [WorkdayJobPosting] {
        var descriptor = FetchDescriptor<WorkdayJobPosting>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\.firstSeenAt, order: .reverse)]
        )
        descriptor.fetchLimit = max(1, limit)
        return try context.fetch(descriptor)
    }

    func deleteWorkdayPosting(id: UUID) throws {
        guard let posting = try fetchWorkdayPosting(id: id) else { return }
        context.delete(posting)
        ModelMergeCoalescer.scheduleSave(context)
    }
}