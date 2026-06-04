// AcademicProfileEntity+Extensions.swift
// Feature: Academics
// Purpose: Academics module — AcademicProfileStatus.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftUI

// MARK: - Academic profile status

enum AcademicProfileStatus: String, CaseIterable, Identifiable {
    case active
    case completed
    case paused
    case transferred

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .active: return String(localized: "academic.profile.status.active")
        case .completed: return String(localized: "academic.profile.status.completed")
        case .paused: return String(localized: "academic.profile.status.paused")
        case .transferred: return String(localized: "academic.profile.status.transferred")
        }
    }
}

// MARK: - Short labels & accent colors

enum AcademicProfilePresentation {
    static let accentPalette: [Color] = [
        Color(red: 0.20, green: 0.45, blue: 0.95),
        Color(red: 0.52, green: 0.32, blue: 0.88),
        Color(red: 0.95, green: 0.45, blue: 0.18),
        Color(red: 0.22, green: 0.72, blue: 0.42),
        Color(red: 0.92, green: 0.32, blue: 0.55),
        Color(red: 0.18, green: 0.68, blue: 0.78),
    ]

    static func accentColor(index: Int) -> Color {
        let palette = accentPalette
        guard !palette.isEmpty else { return .accentColor }
        let i = ((index % palette.count) + palette.count) % palette.count
        return palette[i]
    }

    static func baseShortLabel(for degreeLevel: String?) -> String {
        let canonical = DegreeConfiguration.canonicalLevel(degreeLevel ?? "")
        switch canonical {
        case DegreeConfiguration.undergraduate:
            return String(localized: "academic.profile.label.bachelors")
        case DegreeConfiguration.graduate:
            return String(localized: "academic.profile.label.masters")
        case DegreeConfiguration.doctorateProfessional:
            return String(localized: "academic.profile.label.phd")
        case DegreeConfiguration.lawSchool:
            return String(localized: "academic.profile.label.law")
        case DegreeConfiguration.dentalSchool:
            return String(localized: "academic.profile.label.dental")
        case DegreeConfiguration.medicalSchool:
            return String(localized: "academic.profile.label.medical")
        default:
            let trimmed = (degreeLevel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return String(localized: "academic.profile.label.degree") }
            return trimmed.split(separator: " ").first.map(String.init) ?? trimmed
        }
    }

    static func shortLabels(for profiles: [AcademicProfile]) -> [UUID: String] {
        var numbered: [(id: UUID, number: Int)] = []
        var typed: [(id: UUID, base: String)] = []

        for (index, profile) in profiles.enumerated() {
            let majors = AcademicProfileProgramLists.majors(from: profile)
            let effective = DeclaredProgramDegreeMetadata.effectiveMetadata(
                majors: majors,
                storedDegreeType: profile.degreeType,
                storedDegreeLevel: profile.degreeLevel,
                catalogFallback: nil
            )
            if let effective {
                let label = CatalogDegreeTypeFilter.tabDisplayLabel(forDegreeType: effective.fullDegreeType)
                typed.append((profile.id, label.isEmpty ? effective.fullDegreeType : label))
            } else {
                let type = profile.degreeType?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if type.isEmpty {
                    numbered.append((profile.id, index + 1))
                } else {
                    let label = CatalogDegreeTypeFilter.tabDisplayLabel(forDegreeType: type)
                    typed.append((profile.id, label.isEmpty ? type : label))
                }
            }
        }

        var result: [UUID: String] = [:]
        var baseCounts: [String: Int] = [:]
        for entry in typed {
            let next = (baseCounts[entry.base] ?? 0) + 1
            baseCounts[entry.base] = next
            result[entry.id] = next == 1 ? entry.base : "\(entry.base) \(next)"
        }
        for entry in numbered {
            result[entry.id] = String(
                format: String(
                    localized: "academic.profile.label.degree_number",
                    defaultValue: "Degree %lld"
                ),
                entry.number
            )
        }
        return result
    }
}

extension AcademicProfile {
    var statusEnum: AcademicProfileStatus {
        AcademicProfileStatus(rawValue: status) ?? .active
    }

    var accentColor: Color {
        AcademicProfilePresentation.accentColor(index: Int(accentColorIndex))
    }

    func resolvedShortLabel(among profiles: [AcademicProfile]) -> String {
        AcademicProfilePresentation.shortLabels(for: profiles)[id]
            ?? String(localized: "academic.profile.label.degree", defaultValue: "Degree")
    }

    func effectiveUniversityName(
        among profiles: [AcademicProfile],
        fallbackCollege: String? = nil
    ) -> String {
        let own = collegeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !own.isEmpty { return own }

        if let primary = profiles.first(where: \.isPrimary) {
            let primaryCollege = primary.collegeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !primaryCollege.isEmpty { return primaryCollege }
        }

        for sibling in profiles where id != sibling.id {
            let siblingCollege = sibling.collegeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !siblingCollege.isEmpty { return siblingCollege }
        }

        return fallbackCollege?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
