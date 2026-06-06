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
