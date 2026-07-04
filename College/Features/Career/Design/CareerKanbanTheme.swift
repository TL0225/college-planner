// CareerKanbanTheme.swift
// Feature: Career
// Purpose: Career module — PillStyle.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import CollegeCareer

enum CareerKanbanTheme {
    struct PillStyle: Sendable {
        let foreground: Color
        let background: Color
        let stroke: Color
    }

    static func laneAccent(for status: CareerApplicationStatus) -> Color {
        switch status {
        case .interested: return DesignSystem.Colors.careerLaneInterested
        case .applied: return DesignSystem.Colors.careerLaneApplied
        case .interviewing: return DesignSystem.Colors.careerLaneInterviewing
        case .offer: return DesignSystem.Colors.careerLaneOffer
        case .rejected: return DesignSystem.Colors.careerLaneRejected
        case .accepted: return DesignSystem.Colors.careerLaneAccepted
        }
    }

    static func laneSurface(for status: CareerApplicationStatus) -> Color {
        laneAccent(for: status).opacity(0.05)
    }

    static var cardBackground: Color { DesignSystem.Colors.careerCardBackground }

    static var payGreen: Color { DesignSystem.Colors.careerPayGreen }

    enum Priority: String, CaseIterable, Codable, Sendable {
        case high
        case medium
        case low
    }

    static func priorityPill(_ priority: Priority) -> PillStyle {
        switch priority {
        case .high:
            return PillStyle(
                foreground: DesignSystem.Colors.labelOnFilled,
                background: DesignSystem.Colors.error.opacity(0.92),
                stroke: Color.clear
            )
        case .medium:
            return PillStyle(
                foreground: DesignSystem.Colors.textMain.opacity(0.92),
                background: DesignSystem.Colors.warning.opacity(0.92),
                stroke: Color.clear
            )
        case .low:
            return PillStyle(
                foreground: DesignSystem.Colors.textMain.opacity(0.78),
                background: DesignSystem.Colors.secondary.opacity(0.12),
                stroke: DesignSystem.Colors.textMain.opacity(0.06)
            )
        }
    }

    static func keywordPill(for status: CareerApplicationStatus) -> PillStyle {
        let accent = laneAccent(for: status)
        return PillStyle(
            foreground: accent.opacity(0.92),
            background: accent.opacity(0.12),
            stroke: accent.opacity(0.18)
        )
    }
}

