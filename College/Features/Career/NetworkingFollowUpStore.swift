// NetworkingFollowUpStore.swift
// Feature: Career
// Purpose: Career module — NetworkingFollowUpStore.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import Observation

enum NetworkingFollowUpItem: Identifiable, Equatable, Hashable {
    case job(UUID)
    case contact(UUID)

    var id: String {
        switch self {
        case .job(let uuid): "job:\(uuid.uuidString)"
        case .contact(let uuid): "contact:\(uuid.uuidString)"
        }
    }
}

/// Merges networking-queue jobs with orphan recruiter contacts for a single hybrid surface.
@Observable
@MainActor
final class NetworkingFollowUpStore {
    private(set) var items: [NetworkingFollowUpItem] = []

    private let repo: CareerRepository

    init(repository: CareerRepository = AppDataStore.shared.careerRepository) {
        self.repo = repository
        merge()
    }

    func refresh() {
        merge()
    }

    private func merge() {
        let jobItems = ((try? repo.fetchNetworkingQueueApplications()) ?? [])
            .map { NetworkingFollowUpItem.job($0.id) }
        let contactItems = ((try? repo.fetchOrphanRecruiterContacts()) ?? [])
            .map { NetworkingFollowUpItem.contact($0.id) }
        items = jobItems + contactItems
    }
}
