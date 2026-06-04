// WorkdayReadBridge.swift
// Feature: Career
// Purpose: Career module — WorkdayReadBridge.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// local store-only Workday job-board reads (Phase 7f).
@MainActor
enum WorkdayReadBridge {
    static func companyPostings(companySlug: String) -> [WorkdayJobPosting] {
        let repo = AppDataStore.shared.careerRepository
        return (try? repo.fetchCompanyPostings(companySlug: companySlug)) ?? []
    }

    static func recentActivePostings(limit: Int = 5) -> [WorkdayJobPosting] {
        let repo = AppDataStore.shared.careerRepository
        return (try? repo.fetchRecentActivePostings(limit: limit)) ?? []
    }

    static func posting(companySlug: String, externalPath: String) -> WorkdayJobPosting? {
        let repo = AppDataStore.shared.careerRepository
        return try? repo.fetchPosting(companySlug: companySlug, externalPath: externalPath)
    }
}
