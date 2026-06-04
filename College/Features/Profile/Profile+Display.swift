// Profile+Display.swift
// Feature: Profile
// Purpose: Profile module — Profile+Display.
// Data: CollegePersistence / repositories when applicable.

import Foundation

extension Profile {
    static let welcomePlaceholder = "Welcome!"

    var trimmedDisplayName: String? {
        guard let raw = name?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return raw
    }

    var greetingFirstName: String? {
        guard let trimmed = trimmedDisplayName else { return nil }
        let first = trimmed.components(separatedBy: " ").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return first.isEmpty ? nil : first
    }

    var overviewWelcomeTitle: String {
        if let first = greetingFirstName { return "Welcome back, \(first)." }
        return Self.welcomePlaceholder
    }

    var navBarDisplayLabel: String {
        trimmedDisplayName ?? Self.welcomePlaceholder
    }

    var avatarInitials: String {
        ProfileShellSnapshot.initials(from: trimmedDisplayName)
    }
}
