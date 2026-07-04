// CareerRepository.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CareerRepository.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData
import CollegeCareer

/// Bounded local store fetch helpers for career tracking (Phase 7b).
@MainActor
struct CareerRepository {
    let context: ModelContext

    func fetchApplications(limit: Int = 100, offset: Int = 0) throws -> [JobApplication] {
        var descriptor = FetchDescriptor<JobApplication>(
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        descriptor.fetchLimit = max(1, min(limit, 250))
        descriptor.fetchOffset = max(0, offset)
        return try context.fetch(descriptor)
    }

    func fetchApplication(id: UUID) throws -> JobApplication? {
        var descriptor = FetchDescriptor<JobApplication>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchRecruiterContact(id: UUID) throws -> RecruiterContact? {
        var descriptor = FetchDescriptor<RecruiterContact>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchActiveJobBoardPostings(limit: Int = 80) throws -> [JobBoardPosting] {
        var descriptor = FetchDescriptor<JobBoardPosting>(
            predicate: #Predicate { $0.isActive == true },
            sortBy: [SortDescriptor(\.title, order: .forward)]
        )
        descriptor.fetchLimit = max(1, limit)
        return try context.fetch(descriptor)
    }

    func fetchUpcomingEvents(limit: Int = 60) throws -> [CareerEvent] {
        var descriptor = FetchDescriptor<CareerEvent>(
            predicate: #Predicate { $0.completed == false },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        descriptor.fetchLimit = max(1, limit)
        return try context.fetch(descriptor)
    }

    struct CareerPipelineMetrics: Equatable, Sendable {
        var totalApplied: Int
        var interviews: Int
        var offers: Int

        var interviewRate: Int {
            guard totalApplied > 0 else { return 0 }
            return Int((Double(interviews) / Double(totalApplied) * 100).rounded())
        }

        var offerRate: Int {
            guard totalApplied > 0 else { return 0 }
            return Int((Double(offers) / Double(totalApplied) * 100).rounded())
        }

        static let zero = CareerPipelineMetrics(totalApplied: 0, interviews: 0, offers: 0)
    }

    struct CareerNetworkingKPIs: Equatable, Sendable {
        var contacts: Int
        var followUpsQueued: Int
        var coffeeEvents: Int
        static let zero = CareerNetworkingKPIs(contacts: 0, followUpsQueued: 0, coffeeEvents: 0)
    }

    func pipelineMetrics() throws -> CareerPipelineMetrics {
        let applications = try fetchApplications(limit: 250)
        func count(statuses: [CareerApplicationStatus]) -> Int {
            let rawValues = Set(statuses.map(\.rawValue))
            return applications.filter { rawValues.contains($0.statusRaw) }.count
        }
        return CareerPipelineMetrics(
            totalApplied: count(statuses: [.applied, .interviewing, .offer, .accepted]),
            interviews: count(statuses: [.interviewing, .offer, .accepted]),
            offers: count(statuses: [.offer, .accepted])
        )
    }

    func statusCounts() throws -> [CareerApplicationStatus: Int] {
        let applications = try fetchApplications(limit: 250)
        var counts: [CareerApplicationStatus: Int] = [:]
        for status in CareerApplicationStatus.allCases {
            let count = applications.filter { $0.statusRaw == status.rawValue }.count
            if count > 0 {
                counts[status] = count
            }
        }
        return counts
    }

    func fetchNetworkingQueue(limit: Int = 10) throws -> [JobApplication] {
        let appliedRaw = CareerApplicationStatus.applied.rawValue
        let interviewingRaw = CareerApplicationStatus.interviewing.rawValue
        let applications = try fetchApplications(limit: 250)
        return Array(
            applications
                .filter { $0.statusRaw == appliedRaw || $0.statusRaw == interviewingRaw }
                .sorted { lhs, rhs in
                    let lUpdated = lhs.updatedAt ?? .distantFuture
                    let rUpdated = rhs.updatedAt ?? .distantFuture
                    if lUpdated != rUpdated { return lUpdated < rUpdated }
                    return lhs.sortOrder < rhs.sortOrder
                }
                .prefix(max(1, min(limit, 50)))
        )
    }
}