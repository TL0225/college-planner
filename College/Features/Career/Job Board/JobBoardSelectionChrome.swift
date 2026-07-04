// JobBoardSelectionChrome.swift
// Feature: Career / Job Board
// Purpose: Shared minimal selection styling for openings sidebar and job rows.

import SwiftUI

enum JobBoardSelectionChrome {
    static let barWidth: CGFloat = 3
    static let cornerRadius: CGFloat = 8

    static func rowFill(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected { return DesignSystem.Colors.primary.opacity(0.07) }
        if isHovered { return Color.primary.opacity(0.035) }
        return .clear
    }

    static func rowStroke(isSelected: Bool) -> Color {
        isSelected ? DesignSystem.Colors.primary.opacity(0.22) : Color.primary.opacity(0.06)
    }

    static func rowStrokeWidth(isSelected: Bool) -> CGFloat {
        isSelected ? 1 : 0.5
    }

    static func titleColor(isSelected: Bool, isMuted: Bool) -> Color {
        if isSelected { return DesignSystem.Colors.textMain }
        if isMuted { return DesignSystem.Colors.textLight }
        return DesignSystem.Colors.textMain.opacity(0.92)
    }

    static func titleWeight(isSelected: Bool) -> Font.Weight {
        isSelected ? .semibold : .medium
    }
}

struct JobBoardSelectionRowBackground: View {
    let isSelected: Bool
    var isHovered: Bool = false
    var showsBar: Bool = true

    var body: some View {
        RoundedRectangle(cornerRadius: JobBoardSelectionChrome.cornerRadius, style: .continuous)
            .fill(JobBoardSelectionChrome.rowFill(isSelected: isSelected, isHovered: isHovered))
            .overlay {
                RoundedRectangle(cornerRadius: JobBoardSelectionChrome.cornerRadius, style: .continuous)
                    .strokeBorder(
                        JobBoardSelectionChrome.rowStroke(isSelected: isSelected),
                        lineWidth: JobBoardSelectionChrome.rowStrokeWidth(isSelected: isSelected)
                    )
            }
            .overlay(alignment: .leading) {
                if isSelected, showsBar {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(DesignSystem.Colors.primary)
                        .frame(width: JobBoardSelectionChrome.barWidth)
                        .padding(.leading, 3)
                        .padding(.vertical, 5)
                }
            }
    }
}

struct JobBoardSidebarSelectionBackground: View {
    let isSelected: Bool
    var isHovered: Bool = false

    var body: some View {
        JobBoardSelectionRowBackground(isSelected: isSelected, isHovered: isHovered, showsBar: true)
    }
}
