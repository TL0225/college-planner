// AvailabilityLinkService.swift
// Feature: Core
// Purpose: Core module — Link.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Phase 8 decision gate: **local-only** availability links (no cloud v1).
enum AvailabilityLinkDecision {
    static let mode: Mode = .localHTTP

    enum Mode: String, Sendable {
        case localHTTP
        case cloudDeferred
    }
}

/// Serves read-only free/busy snapshots for share links (local HTTP stub).
actor AvailabilityLinkService {
    static let shared = AvailabilityLinkService()

    struct Link: Codable, Identifiable, Sendable {
        var id: UUID
        var title: String
        var createdAt: Date
    }

    private var links: [Link] = []

    func createLink(title: String) -> Link {
        let link = Link(id: UUID(), title: title, createdAt: Date())
        links.append(link)
        persist()
        return link
    }

    func allLinks() -> [Link] { links }

    private func persist() {
        if let data = try? JSONEncoder().encode(links) {
            UserDefaults.standard.set(data, forKey: "calendar.availabilityLinks")
        }
    }

    func restore() {
        guard let data = UserDefaults.standard.data(forKey: "calendar.availabilityLinks"),
              let decoded = try? JSONDecoder().decode([Link].self, from: data)
        else { return }
        links = decoded
    }
}
