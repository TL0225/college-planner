// GraduationTimelineEngine.swift
// Feature: Academics
// Purpose: Academics module — TermState.
// Data: CollegePersistence / repositories when applicable.

// GraduationTimelineEngine.swift
// Pure-calc helpers driving the Graduation Timeline configuration sheet.
// No SwiftUI, no local store writes — takes inputs in, returns summary/state
// values out. Designed so the sheet UI can recompute live as the user adjusts
// sliders / pickers without touching the store until they hit Save.

import Foundation

enum GraduationTimelineEngine {

    // MARK: - Inputs

    enum TermRole: String, Codable, Equatable {
        case completed
        case inProgress
        case future
    }

    /// One enumerated term between the user's "start" reference and the chosen
    /// target. `actualCredits` reflects credits already on the planner for this
    /// term; `plannedCap` is the sheet's user-editable cap. Historical / in-progress
    /// terms are passed through with `role != .future` so the UI can disable their
    /// stepper.
    struct TermState: Identifiable, Equatable {
        let id: String
        let year: Int
        let season: String
        let isHistorical: Bool
        let isCurrent: Bool
        let actualCredits: Int
        let plannedCap: Int
        let role: TermRole

        var label: String { "\(season) \(year)" }
    }

    enum CreditState: Equatable {
        case sufficient        // within full-time → max-overload band
        case underAllocated    // > 0 but below full-time threshold
        case belowFullTime     // 0 credits planned for a future term
        case overloaded        // strictly above max-overload band
        case criticalOverload  // beyond the critical/burnout threshold
    }

    struct TermStatus: Equatable {
        let state: CreditState
        let warnings: [String]
    }

    /// Top-line numbers shown in the sheet's pacing header.
    struct Summary: Equatable {
        let completed: Int
        let inProgress: Int
        let planned: Int
        let requiredTotal: Int
        let remainingNeeded: Int
        let allocatedAcrossFutureTerms: Int
        let deficitToTarget: Int
        let avgPaceNeeded: Double
        let isAchievable: Bool
    }

    // MARK: - Term enumeration

    /// Walk from `(startYear, startSeason)` through `(endYear, endSeason)` inclusive.
    /// Includes only the four canonical seasons (Spring → Summer → Fall → Winter).
    /// Returns empty when the end is before the start.
    static func enumerateTerms(
        from start: (year: Int, season: String),
        through end: (year: Int, season: String)
    ) -> [(year: Int, season: String)] {
        let seasons = ["Spring", "Summer", "Fall", "Winter"]
        let startSeasonIdx = seasons.firstIndex { $0.caseInsensitiveCompare(start.season) == .orderedSame } ?? 0
        let endSeasonIdx = seasons.firstIndex { $0.caseInsensitiveCompare(end.season) == .orderedSame } ?? 0

        var year = start.year
        var seasonIdx = startSeasonIdx
        var out: [(Int, String)] = []
        // Stop after at most 8 years (32 terms) to keep things bounded even when
        // an unparseable target slips through.
        let hardCap = 32
        while out.count < hardCap {
            out.append((year, seasons[seasonIdx]))
            if year == end.year && seasonIdx == endSeasonIdx { break }
            if year > end.year || (year == end.year && seasonIdx > endSeasonIdx) {
                break
            }
            seasonIdx += 1
            if seasonIdx >= seasons.count {
                seasonIdx = 0
                year += 1
            }
        }
        return out
    }

    /// Current term given today's date. Spring/Summer/Fall/Winter map roughly to
    /// the Northern-Hemisphere academic calendar (Jan–May Spring, Jun–Aug Summer,
    /// Sep–Nov Fall, Dec Winter). Used as the start anchor when the sheet opens.
    static func currentTerm(now: Date = Date(), calendar: Calendar = .current) -> (year: Int, season: String) {
        let comps = calendar.dateComponents([.year, .month], from: now)
        let year = comps.year ?? 2024
        let month = comps.month ?? 1
        switch month {
        case 1...5:  return (year, "Spring")
        case 6...8:  return (year, "Summer")
        case 9...11: return (year, "Fall")
        default:     return (year, "Winter")
        }
    }

    // MARK: - Summary computation

    static func summary(
        completed: Int,
        inProgress: Int,
        planned: Int,
        requiredTotal: Int,
        futureCaps: [Int]
    ) -> Summary {
        let allocated = futureCaps.reduce(0, +)
        let remaining = max(0, requiredTotal - completed - inProgress - planned)
        let deficit = max(0, remaining - allocated)
        let denom = max(1, futureCaps.count)
        let pace = Double(remaining) / Double(denom)
        return Summary(
            completed: completed,
            inProgress: inProgress,
            planned: planned,
            requiredTotal: requiredTotal,
            remainingNeeded: remaining,
            allocatedAcrossFutureTerms: allocated,
            deficitToTarget: deficit,
            avgPaceNeeded: pace.isFinite ? pace : 0,
            isAchievable: deficit == 0
        )
    }

    // MARK: - Per-term status

    /// Policy bands used by `status(forTerm:)`. Pulled from `SchoolPolicies` when
    /// available, otherwise from the safe defaults below.
    struct PolicyBand {
        let minFullTime: Int
        let maxOverload: Int
        let criticalOverload: Int
    }

    static let defaultUndergradBand = PolicyBand(minFullTime: 12, maxOverload: 18, criticalOverload: 21)
    static let defaultGraduateBand = PolicyBand(minFullTime: 9, maxOverload: 15, criticalOverload: 18)

    /// Pick the right band given a school's `SchoolPolicies` (if any) and the
    /// student's degree level. Graduate-level degrees use the looser graduate
    /// defaults when a school doesn't publish its own cap.
    static func policyBand(
        policies: SchoolPolicies?,
        isGraduate: Bool
    ) -> PolicyBand {
        let defaults = isGraduate ? defaultGraduateBand : defaultUndergradBand
        guard let policies else { return defaults }
        return PolicyBand(
            minFullTime: policies.minCreditsForFullTime ?? defaults.minFullTime,
            maxOverload: policies.maxCreditsPerSemester ?? defaults.maxOverload,
            // Most catalogs don't publish a "critical" threshold; +3 over the
            // overload cap is the conservative heuristic the AI assistant uses.
            criticalOverload: (policies.maxCreditsPerSemester ?? defaults.maxOverload) + 3
        )
    }

    static func status(
        forCap cap: Int,
        isHistorical: Bool,
        isCurrent: Bool,
        band: PolicyBand
    ) -> TermStatus {
        // Historical / in-progress rows display informational warnings only.
        if isHistorical {
            return TermStatus(state: .sufficient, warnings: [])
        }
        if isCurrent {
            return TermStatus(state: .sufficient, warnings: [])
        }
        if cap <= 0 {
            return TermStatus(state: .belowFullTime, warnings: [
                "No credits allocated for this term — graduation pacing drops."
            ])
        }
        if cap < band.minFullTime {
            return TermStatus(state: .underAllocated, warnings: [
                "\(cap) credits is below the \(band.minFullTime)-credit full-time minimum — financial aid may be affected."
            ])
        }
        if cap >= band.criticalOverload {
            return TermStatus(state: .criticalOverload, warnings: [
                "\(cap) credits exceeds the safe-load cap (\(band.criticalOverload)+). Most students burn out at this pace."
            ])
        }
        if cap > band.maxOverload {
            return TermStatus(state: .overloaded, warnings: [
                "\(cap) credits is above the standard \(band.maxOverload)-credit overload cap — confirm with your advisor."
            ])
        }
        return TermStatus(state: .sufficient, warnings: [])
    }

    // MARK: - Recommended even-split reset

    /// Even distribution of `remainingCredits` across `futureTermCount`, clamped
    /// to `[minFullTime, maxOverload]`. Distributes the remainder one credit at a
    /// time across earlier terms so totals add up exactly (within the band).
    /// When `futureTermCount == 0` returns an empty array (caller should disable
    /// the Save button in that case).
    static func recommendedEvenSplit(
        remainingCredits: Int,
        futureTermCount: Int,
        band: PolicyBand
    ) -> [Int] {
        guard futureTermCount > 0 else { return [] }
        guard remainingCredits > 0 else {
            return Array(repeating: 0, count: futureTermCount)
        }
        let baseFloat = Double(remainingCredits) / Double(futureTermCount)
        let baseInt = Int(baseFloat.rounded(.down))
        var leftover = remainingCredits - (baseInt * futureTermCount)
        var caps = Array(repeating: baseInt, count: futureTermCount)
        // Sprinkle the leftover credits onto the earliest terms first.
        var i = 0
        while leftover > 0 {
            caps[i] += 1
            leftover -= 1
            i = (i + 1) % futureTermCount
        }
        // Clamp each entry to the band so the recommendation never trips the
        // overload warnings on its own.
        caps = caps.map { min(band.maxOverload, max(band.minFullTime, $0)) }
        return caps
    }

    // MARK: - Pacing helpers

    /// Total credits left to graduate after subtracting everything currently on
    /// the planner (completed + in-progress + planned). Used by the header.
    static func remainingCreditsToGraduate(
        completed: Int,
        inProgress: Int,
        planned: Int,
        requiredTotal: Int
    ) -> Int {
        max(0, requiredTotal - completed - inProgress - planned)
    }

    /// Suggest the next 8 candidate target terms following the user's current term.
    /// Useful for the target-graduation picker pill row.
    static func suggestTargetTerms(
        from start: (year: Int, season: String),
        count: Int = 8
    ) -> [(year: Int, season: String)] {
        let seasons = ["Spring", "Summer", "Fall", "Winter"]
        let startSeasonIdx = seasons.firstIndex { $0.caseInsensitiveCompare(start.season) == .orderedSame } ?? 0
        var year = start.year
        var seasonIdx = startSeasonIdx
        var out: [(Int, String)] = []
        // Skip the current term — the picker is asking "when do you graduate?",
        // so the earliest valid pick is one term out.
        for _ in 0..<count {
            seasonIdx += 1
            if seasonIdx >= seasons.count {
                seasonIdx = 0
                year += 1
            }
            out.append((year, seasons[seasonIdx]))
        }
        return out
    }
}
