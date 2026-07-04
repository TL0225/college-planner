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

    // MARK: Completed (semantic success)
    static let completedDot      = DesignSystem.Colors.success
    static let completedPillBG   = DesignSystem.Colors.success.opacity(0.14)
    static let completedPillFG   = DesignSystem.Colors.success.opacity(0.85)

    // MARK: In Progress (semantic warning)
    static let inProgressDot     = DesignSystem.Colors.warning
    static let inProgressPillBG  = DesignSystem.Colors.warning.opacity(0.14)
    static let inProgressPillFG  = DesignSystem.Colors.warning.opacity(0.85)

    // MARK: Planned (semantic secondary)
    static let plannedDot        = DesignSystem.Colors.secondary
    static let plannedPillBG     = DesignSystem.Colors.secondary.opacity(0.14)
    static let plannedPillFG     = DesignSystem.Colors.secondary.opacity(0.85)

    // MARK: Remaining (neutral adaptive)
    static let remainingDot      = DesignSystem.Colors.textLight.opacity(0.55)
    static let remainingPillBG   = DesignSystem.Colors.textLight.opacity(0.10)
    static let remainingPillFG   = DesignSystem.Colors.textLight

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

    /// Map a single planner course's stored status into the four-state palette. Used by the
    /// semester course popover so each course bullet matches the semester pill semantics.
    static func state(forStatus rawStatus: String, isCompleted: Bool) -> State {
        if isCompleted { return .completed }
        switch rawStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "completed":                    return .completed
        case "in progress", "in-progress":   return .inProgress
        case "dropped", "failed", "not planned", "not-planned":
            return .remaining
        default:                             return .planned
        }
    }
}

