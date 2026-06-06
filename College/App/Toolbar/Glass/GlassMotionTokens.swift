// GlassMotionTokens.swift
// Feature: App / Toolbar / Glass

import SwiftUI

struct GlassMotionTokens: Equatable, Sendable {
    var hoverScale: CGFloat = 1.04
    var pressedScale: CGFloat = 0.96
    var hoverElevation: CGFloat = 1
    var pressCompression: CGFloat = 0.98
    var spring: Animation = .spring(response: 0.28, dampingFraction: 0.78)
    var stateTransition: Animation = .spring(response: 0.22, dampingFraction: 0.82)
}
