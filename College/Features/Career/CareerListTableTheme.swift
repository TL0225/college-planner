// CareerListTableTheme.swift
// Feature: Career
// Purpose: Career module — StageBadgeStyle.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

enum CareerListTableTheme {
    struct StageBadgeStyle: Sendable {
        let dot: Color
        let foreground: Color
        let background: Color
    }

    struct PillStyle: Sendable {
        let foreground: Color
        let background: Color
    }

    static func stageBadgeStyle(for status: CareerApplicationStatus) -> StageBadgeStyle {
        let accent = CareerKanbanTheme.laneAccent(for: status)
        switch status {
        case .interested, .applied:
            return StageBadgeStyle(
                dot: DesignSystem.Colors.secondary,
                foreground: DesignSystem.Colors.secondary.opacity(0.92),
                background: DesignSystem.Colors.secondary.opacity(0.18)
            )
        case .interviewing:
            return StageBadgeStyle(
                dot: accent,
                foreground: accent.opacity(0.92),
                background: accent.opacity(0.22)
            )
        case .offer, .accepted:
            return StageBadgeStyle(
                dot: DesignSystem.Colors.success,
                foreground: DesignSystem.Colors.success.opacity(0.92),
                background: DesignSystem.Colors.success.opacity(0.18)
            )
        case .rejected:
            return StageBadgeStyle(
                dot: DesignSystem.Colors.error,
                foreground: DesignSystem.Colors.error.opacity(0.92),
                background: DesignSystem.Colors.error.opacity(0.16)
            )
        }
    }

    static var techTagStyle: PillStyle {
        PillStyle(
            foreground: DesignSystem.Colors.tertiaryText,
            background: DesignSystem.Colors.secondary.opacity(0.14)
        )
    }

    static let columnCompany: CGFloat = 200
    static let columnJobTitle: CGFloat = 220
    static let columnStage: CGFloat = 130
    static let columnLocation: CGFloat = 160
    static let columnLastApplied: CGFloat = 120
    static let columnLink: CGFloat = 52
}

struct CareerListStageBadge: View {
    let status: CareerApplicationStatus

    var body: some View {
        let style = CareerListTableTheme.stageBadgeStyle(for: status)
        HStack(spacing: 6) {
            Circle()
                .fill(style.dot)
                .frame(width: 6, height: 6)
            Text(status.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(style.foreground)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .background(style.background, in: Capsule())
    }
}

struct CareerListTechTagPill: View {
    let text: String

    var body: some View {
        let style = CareerListTableTheme.techTagStyle
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(style.foreground)
            .lineLimit(1)
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(style.background, in: Capsule())
    }
}
