// AssistantCareerRolesCatalog.swift
// Feature: Assistant
// Purpose: Backlog placeholder for curated major→roles data (O*NET evaluation).

import Foundation

enum AssistantCareerRolesCatalog {
    /// Future: load bundled JSON keyed by major slug. v1 returns nil → model + disclaimer.
    static func baselineRoles(forMajorDisplay major: String) -> [String]? {
        let normalized = major.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        let seeds: [String: [String]] = [
            "computer science": ["Software engineer", "Data analyst", "Systems administrator", "Product engineer"],
            "electrical engineering": ["Electrical engineer", "Hardware engineer", "Controls engineer", "Test engineer"]
        ]
        for (key, roles) in seeds where normalized.contains(key) {
            return roles
        }
        return nil
    }
}
