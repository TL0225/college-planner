// GlassInteractionState.swift
// Feature: App / Toolbar / Glass

import SwiftUI

enum GlassInteractionState: Equatable, Sendable {
    case idle
    case hover
    case focus
    case pressed
    case selected
    case disabled
}

struct GlassInteractiveSurface<Content: View>: View {
    @Environment(\.glassToolbarStyle) private var style
    let interactionState: GlassInteractionState
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .opacity(style.opacity(for: interactionState))
            .scaleEffect(style.scale(for: interactionState))
            .animation(style.motion.stateTransition, value: interactionState)
    }
}

extension View {
    func glassInteractiveSurface(_ state: GlassInteractionState) -> some View {
        GlassInteractiveSurface(interactionState: state, content: { self })
    }
}
