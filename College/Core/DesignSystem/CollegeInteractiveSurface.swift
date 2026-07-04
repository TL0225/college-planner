// CollegeInteractiveSurface.swift
// Feature: Core / DesignSystem
// Purpose: Shared cursor hover + press feedback (Part 26 / M30-085–087).

import SwiftUI

enum CollegeInteractiveRole {
    case card
    case row
    case toolbar
    case cta
}

struct CollegeInteractiveSurface: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("ui.reduceMotion") private var appReduceMotion = false
    @State private var isHovered = false
    @State private var isPressed = false

    var role: CollegeInteractiveRole
    var hoverScaleEnabled: Bool

    init(role: CollegeInteractiveRole = .card, hoverScaleEnabled: Bool = true) {
        self.role = role
        self.hoverScaleEnabled = hoverScaleEnabled
    }

    private var motionReduced: Bool {
        CollegeReduceMotionGate.isReduced(
            accessibilityReduceMotion: systemReduceMotion,
            appReduceMotion: appReduceMotion
        )
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .shadow(
                color: .black.opacity(isHovered && !isPressed && role != .toolbar ? 0.08 : 0),
                radius: 6,
                y: 3
            )
            .animation(CollegeMotion.cursorSpring(reduced: motionReduced), value: isHovered)
            .animation(CollegeMotion.pressSpring(reduced: motionReduced), value: isPressed)
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    isHovered = true
                case .ended:
                    isHovered = false
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
    }

    private var scale: CGFloat {
        if motionReduced { return 1 }
        if isPressed { return role == .cta ? 0.96 : 0.97 }
        guard hoverScaleEnabled, isHovered else { return 1 }
        switch role {
        case .cta: return 1.03
        case .toolbar: return 1.015
        case .row: return 1.01
        case .card: return 1.02
        }
    }
}

extension View {
    func collegeInteractiveSurface(
        _ role: CollegeInteractiveRole = .card,
        hoverScaleEnabled: Bool = true
    ) -> some View {
        modifier(CollegeInteractiveSurface(role: role, hoverScaleEnabled: hoverScaleEnabled))
    }
}
