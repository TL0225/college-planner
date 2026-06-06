// ToolbarDensity.swift
// Feature: App / Toolbar / Glass

import SwiftUI

enum ToolbarDensity: Equatable, Sendable {
    case compact
    case regular
    case expanded

    static func derived(from visibility: NavigationSplitViewVisibility) -> ToolbarDensity {
        switch visibility {
        case .detailOnly: return .compact
        case .all, .doubleColumn: return .expanded
        default: return .regular
        }
    }
}

private struct ToolbarDensityKey: EnvironmentKey {
    static let defaultValue: ToolbarDensity = .regular
}

extension EnvironmentValues {
    var toolbarDensity: ToolbarDensity {
        get { self[ToolbarDensityKey.self] }
        set { self[ToolbarDensityKey.self] = newValue }
    }
}

// MARK: - Density v2 (theme scaling)

extension ToolbarGlassTheme {
    /// Applies compact/expanded multipliers to all glass metrics for the active sidebar layout.
    func scaled(for density: ToolbarDensity) -> ToolbarGlassTheme {
        var copy = self
        switch density {
        case .compact:
            copy.circleControlSize *= 0.9
            copy.iconPointSize *= 0.92
            copy.groupInset *= 0.85
            copy.searchFieldWidth *= 0.85
            copy.groupSpacing *= 0.9
            copy.controlPadding *= 0.9
        case .expanded:
            copy.circleControlSize *= 1.05
            copy.iconPointSize *= 1.05
            copy.groupInset *= 1.1
            copy.searchFieldWidth *= 1.1
            copy.groupSpacing *= 1.05
            copy.controlPadding *= 1.05
        case .regular:
            break
        }
        return copy
    }
}

extension GlassToolbarStyle {
    func effectiveTheme(for density: ToolbarDensity) -> ToolbarGlassTheme {
        theme.scaled(for: density)
    }
}
