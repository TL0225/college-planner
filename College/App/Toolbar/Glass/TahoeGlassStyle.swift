// TahoeGlassStyle.swift
// Feature: App / Toolbar / Glass — macOS 26 default

import SwiftUI

struct TahoeGlassStyle: GlassToolbarStyle {
    let theme = ToolbarGlassTheme()
    let motion = GlassMotionTokens()

    func material(for state: GlassInteractionState) -> Material {
        switch state {
        case .disabled: return .thinMaterial
        default: return .regularMaterial
        }
    }
}
