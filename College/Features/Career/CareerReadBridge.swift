// CareerReadBridge.swift
// Feature: Career
// Purpose: Career module — CareerApplicationStatsRow.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData
import CollegeCareer

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
