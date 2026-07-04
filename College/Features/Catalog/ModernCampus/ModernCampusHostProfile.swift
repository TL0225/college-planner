// ModernCampusHostProfile.swift
// Feature: Catalog
// Purpose: Host registry for Modern Campus heuristics and synonym labels.
// Data: CollegePersistence / repositories when applicable.

import Foundation

struct ModernCampusHostProfile: Sendable, Equatable {
    let id: String
    let hostNeedles: [String]
    let prefersEntityPageProgramDiscovery: Bool
    let navLabelSynonyms: [String]

    func matches(host: String?) -> Bool {
        let normalized = (host ?? "").lowercased()
        guard !normalized.isEmpty else { return false }
        return hostNeedles.contains(where: { normalized.contains($0) })
    }
}

enum ModernCampusHostProfiles {
    /// Wording variants seen across MC catalogs (non-host-specific).
    static let defaultNavLabelSynonyms: [String] = [
        "programs of study",
        "programs & degrees",
        "degrees and programs",
        "academic programs",
        "undergraduate programs",
        "graduate programs",
        "majors and minors",
        "departments & programs",
        "bulletin courses",
        "course descriptions",
    ]

    private static let registry: [ModernCampusHostProfile] = [
        ModernCampusHostProfile(
            id: "ub",
            hostNeedles: ["buffalo.edu"],
            prefersEntityPageProgramDiscovery: true,
            navLabelSynonyms: [
                "departments & programs",
                "department/program",
                "academic programs",
                "professional programs",
                "majors and minors"
            ]
        )
    ]

    static func resolve(host: String?) -> ModernCampusHostProfile? {
        registry.first(where: { $0.matches(host: host) })
    }

    static func navLabelSynonyms(host: String?) -> [String] {
        let hostSpecific = resolve(host: host)?.navLabelSynonyms ?? []
        if hostSpecific.isEmpty { return defaultNavLabelSynonyms }
        return hostSpecific + defaultNavLabelSynonyms
    }
}
