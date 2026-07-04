// ToolbarMetrics.swift
// Feature: Core
// Purpose: Core module — ToolbarMetrics.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Shared sizing + typography for every in-app toolbar.
///
/// All toolbar text uses **SF Pro 12pt** (plain `.system`, not Rounded) so the title, controls,
/// pill labels, and filter chips read as one consistent strip across the app. Only weight varies.
enum ToolbarMetrics {
    static let pointSize: CGFloat = 12

    /// SF Pro 12pt at the requested weight.
    static func font(_ weight: Font.Weight) -> Font {
        .system(size: pointSize, weight: weight)
    }

    static let titleFont   = font(.semibold)
    static let controlFont = font(.semibold)
    static let iconFont    = font(.semibold)
    static let labelFont   = font(.medium)

    static let itemHorizontalPadding: CGFloat = 8
    static let itemSpacing: CGFloat = 12

    static let iconControlSize: CGFloat = 28
    static let minHitTarget: CGFloat = 44
    static let iconHitPadding: CGFloat = (minHitTarget - iconControlSize) / 2

    /// Label for a compact toolbar icon (44pt hit target without stretching the toolbar row).
    @ViewBuilder
    static func glassIconLabel(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(DesignSystem.Fonts.main(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .frame(width: iconControlSize, height: iconControlSize)
            .padding(iconHitPadding)
            .contentShape(Rectangle())
    }
}

extension View {
    /// Borderless toolbar icon chrome: no glass tile, full 44pt hit target on macOS window toolbar.
    func toolbarIconButtonStyle() -> some View {
        buttonStyle(.borderless)
            .controlSize(.small)
            .frame(minWidth: ToolbarMetrics.minHitTarget, minHeight: ToolbarMetrics.minHitTarget)
            .contentShape(Rectangle())
            .collegeInteractiveSurface(.toolbar)
    }

    /// Text/segment controls hosted in the window toolbar.
    func toolbarSegmentButtonStyle() -> some View {
        buttonStyle(.plain)
            .contentShape(Rectangle())
    }
}
