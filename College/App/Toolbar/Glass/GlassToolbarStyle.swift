// GlassToolbarStyle.swift
// Feature: App / Toolbar / Glass

import SwiftUI

protocol GlassToolbarStyle {
    var theme: ToolbarGlassTheme { get }
    var motion: GlassMotionTokens { get }
    func material(for state: GlassInteractionState) -> Material
    func opacity(for state: GlassInteractionState) -> Double
    func scale(for state: GlassInteractionState) -> CGFloat
}

extension GlassToolbarStyle {
    func opacity(for state: GlassInteractionState) -> Double {
        switch state {
        case .idle, .hover, .focus, .selected: return 1
        case .pressed: return 0.92
        case .disabled: return 0.55
        }
    }

    func scale(for state: GlassInteractionState) -> CGFloat {
        switch state {
        case .hover: return motion.hoverScale
        case .pressed: return motion.pressedScale
        case .selected: return 1.02
        default: return 1
        }
    }
}
