// ProfileRepository+GraduationPlan.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — ProfileRepository+GraduationPlan.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension ProfileRepository {
    func fetchGraduationPlanTerms(profileID: UUID) throws -> [GraduationPlanTerm] {
        var descriptor = FetchDescriptor<GraduationPlanTerm>(
            predicate: #Predicate { $0.profileID == profileID },
            sortBy: [
                SortDescriptor(\.year, order: .forward),
                SortDescriptor(\.seasonOrder, order: .forward),
            ]
        )
        descriptor.fetchLimit = 200
        return try context.fetch(descriptor)
    }

    @discardableResult
    func upsertGraduationPlanTerm(
        profileID: UUID,
        year: Int,
        season: String,
        plannedCreditCap: Int,
        note: String? = nil
    ) throws -> GraduationPlanTerm {
        let canonicalSeason = AcademicProgramHelpers.canonicalGraduationSeasonLabel(season)
        let order = AcademicProgramHelpers.graduationSeasonOrder(for: canonicalSeason)
        let intYear = Int16(clamping: year)

        var descriptor = FetchDescriptor<GraduationPlanTerm>(
            predicate: #Predicate { term in
                term.profileID == profileID
                    && term.year == intYear
                    && term.season == canonicalSeason
            }
        )
        descriptor.fetchLimit = 1

        let entity: GraduationPlanTerm
        if let existing = try context.fetch(descriptor).first {
            entity = existing
        } else {
            entity = GraduationPlanTerm(
                profileID: profileID,
                year: intYear,
                season: canonicalSeason,
                seasonOrder: order
            )
            context.insert(entity)
        }
        entity.plannedCreditCap = Int16(clamping: max(0, plannedCreditCap))
        if let note {
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            entity.noteText = trimmed.isEmpty ? nil : trimmed
        }
        ModelMergeCoalescer.scheduleSave(context)
        return entity
    }

    func clearGraduationPlanTerms(profileID: UUID) throws {
        let terms = try fetchGraduationPlanTerms(profileID: profileID)
        guard !terms.isEmpty else { return }
        for term in terms {
            context.delete(term)
        }
        ModelMergeCoalescer.scheduleSave(context)
    }

    func structuredExpectedGraduation(for profile: AcademicProfile) -> (year: Int, season: String)? {
        let year = Int(profile.expectedGraduationYear ?? 0)
        let season = (profile.expectedGraduationSeason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if year > 0, !season.isEmpty {
            return (year, AcademicProgramHelpers.canonicalGraduationSeasonLabel(season))
        }
        return Self.parseExpectedGraduationString(profile.expectedGraduation)
    }

    func setStructuredExpectedGraduation(year: Int, season: String, on profile: AcademicProfile) {
        let canonicalSeason = AcademicProgramHelpers.canonicalGraduationSeasonLabel(season)
        profile.expectedGraduationYear = Int16(clamping: year)
        profile.expectedGraduationSeason = canonicalSeason
        profile.expectedGraduation = "\(canonicalSeason) \(year)"
        ModelMergeCoalescer.scheduleSave(context)
    }

    static func parseExpectedGraduationString(_ raw: String?) -> (year: Int, season: String)? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let yearPattern = try? NSRegularExpression(pattern: #"\b(\d{2,4})\b"#)
        var year: Int?
        if let yearPattern {
            let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
            if let match = yearPattern.firstMatch(in: raw, range: range),
               let yr = Range(match.range, in: raw),
               let value = Int(raw[yr]) {
                year = value < 100 ? 2000 + value : value
            }
        }
        guard let year else { return nil }

        let lower = raw.lowercased()
        let seasonNames = ["spring", "summer", "fall", "winter"]
        var season: String?
        for name in seasonNames where lower.contains(name) {
            season = name.capitalized
            break
        }
        if season == nil {
            let seasonByMonth: [(String, String)] = [
                ("january", "Spring"), ("february", "Spring"), ("march", "Spring"),
                ("april", "Spring"), ("may", "Spring"),
                ("june", "Summer"), ("july", "Summer"), ("august", "Summer"),
                ("september", "Fall"), ("october", "Fall"), ("november", "Fall"),
                ("december", "Winter"),
            ]
            for (month, label) in seasonByMonth where lower.contains(month) {
                season = label
                break
            }
        }
        guard let season else { return nil }
        return (year, season)
    }
}