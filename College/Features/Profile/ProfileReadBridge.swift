// ProfileReadBridge.swift
// Feature: Profile
// Purpose: Profile module — ProfileShellSnapshot.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

struct ProfileShellSnapshot: Equatable, Sendable {
    let displayName: String?
    let collegeName: String?
    let initials: String
    let navBarLabel: String

    static let welcomePlaceholder = "Welcome!"

    static func initials(from displayName: String?) -> String {
        guard let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return "…"
        }
        let parts = trimmed.split(separator: " ").map(String.init)
        if parts.count >= 2 {
            return String((parts[0].first ?? "?")).uppercased()
                + String((parts[1].first ?? "?")).uppercased()
        }
        if let first = parts.first?.first {
            return String(first).uppercased()
        }
        return "?"
    }
}

@MainActor
enum ProfileReadBridge {
    static func shellSnapshot(collegePersistence: CollegePersistence = .shared) -> ProfileShellSnapshot {
        let repo = ProfileRepository(context: collegePersistence.profileContext)
        if let profile = try? repo.fetchPrimaryProfile() {
            let displayName = profile.trimmedDisplayName
            let college = profile.collegeName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return ProfileShellSnapshot(
                displayName: displayName,
                collegeName: (college?.isEmpty == false) ? college : nil,
                initials: profile.avatarInitials,
                navBarLabel: displayName ?? ProfileShellSnapshot.welcomePlaceholder
            )
        }
        return ProfileShellSnapshot(
            displayName: nil,
            collegeName: nil,
            initials: "…",
            navBarLabel: ProfileShellSnapshot.welcomePlaceholder
        )
    }

    static func primaryProfile(collegePersistence: CollegePersistence = .shared) -> Profile? {
        try? collegePersistence.profileRepository.fetchPrimaryProfile()
    }
}
