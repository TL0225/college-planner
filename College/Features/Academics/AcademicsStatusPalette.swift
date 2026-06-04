// AcademicsStatusPalette.swift
// Feature: Academics
// Purpose: Academics module — AcademicsStatusPalette.
// Data: CollegePersistence / repositories when applicable.

// AcademicsStatusPalette.swift
// Single source of truth for status-related colors across the Academics page:
// semester rows, course bullets, category checkmarks, stacked-bar segments, and
// the bottom Completed/InProgress/Remaining strip.
//
// The Figma design uses four states (completed / in progress / planned / remaining)
// each with a "dot" hue, a soft pill background, and a darker pill foreground.

import SwiftUI

enum AcademicsStatusPalette {
    /// Drives the four-state grouping used by audit rows + summary strip + semester pills.
    enum State {
        case completed
        case inProgress
        case planned
        case remaining
    }

    // MARK: Completed (soft green)
    static let completedDot      = Color(red: 0.16, green: 0.74, blue: 0.51)
    static let completedPillBG   = Color(red: 0.16, green: 0.74, blue: 0.51).opacity(0.14)
    static let completedPillFG   = Color(red: 0.10, green: 0.52, blue: 0.36)

    // MARK: In Progress (soft orange)
    static let inProgressDot     = Color(red: 0.95, green: 0.58, blue: 0.20)
    static let inProgressPillBG  = Color(red: 0.95, green: 0.58, blue: 0.20).opacity(0.14)
    static let inProgressPillFG  = Color(red: 0.78, green: 0.43, blue: 0.08)

    // MARK: Planned (soft lavender)
    static let plannedDot        = Color(red: 0.49, green: 0.45, blue: 0.95)
    static let plannedPillBG     = Color(red: 0.49, green: 0.45, blue: 0.95).opacity(0.14)
    static let plannedPillFG     = Color(red: 0.32, green: 0.27, blue: 0.78)

    // MARK: Remaining (neutral)
    static let remainingDot      = Color.secondary.opacity(0.40)
    static let remainingPillBG   = Color.secondary.opacity(0.10)
    static let remainingPillFG   = Color.secondary

    // MARK: Resolvers

    static func dot(for state: State) -> Color {
        switch state {
        case .completed:  return completedDot
        case .inProgress: return inProgressDot
        case .planned:    return plannedDot
        case .remaining:  return remainingDot
        }
    }

    static func pillBackground(for state: State) -> Color {
        switch state {
        case .completed:  return completedPillBG
        case .inProgress: return inProgressPillBG
        case .planned:    return plannedPillBG
        case .remaining:  return remainingPillBG
        }
    }

    static func pillForeground(for state: State) -> Color {
        switch state {
        case .completed:  return completedPillFG
        case .inProgress: return inProgressPillFG
        case .planned:    return plannedPillFG
        case .remaining:  return remainingPillFG
        }
    }

    static func label(for state: State) -> String {
        switch state {
        case .completed:  return "Completed"
        case .inProgress: return "In Progress"
        case .planned:    return "Planned"
        case .remaining:  return "Remaining"
        }
    }
}

// MARK: - RequirementPlanProgress bridge

extension AcademicsStatusPalette {
    /// Map the existing audit `RequirementPlanProgress` into the four-state palette.
    /// `notOnPlan` collapses to `remaining` so unplaced courses render with the neutral dot.
    static func state(for progress: RequirementPlanProgress) -> State {
        switch progress {
        case .completed:  return .completed
        case .inProgress: return .inProgress
        case .planned:    return .planned
        case .notOnPlan:  return .remaining
        }
    }
}

