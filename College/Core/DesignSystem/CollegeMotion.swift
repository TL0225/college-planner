// CollegeMotion.swift
// Feature: Core / DesignSystem
// Purpose: Shared motion timing tokens (Part 26 / M30-051).

import SwiftUI

/// Product-wide motion timings — prefer these over per-feature `easeInOut(0.2)` drift.
enum CollegeMotion {
    static let cursorResponse: Double = 0.12
    static let pressResponse: Double = 0.10
    static let standardResponse: Double = 0.28
    static let narrativeResponse: Double = 0.36
    static let staggerStep: Double = 0.045

    static func cursorSpring(reduced: Bool) -> Animation? {
        reduced ? .easeOut(duration: 0.10) : .spring(response: cursorResponse, dampingFraction: 0.82)
    }

    static func pressSpring(reduced: Bool) -> Animation? {
        reduced ? .easeOut(duration: 0.08) : .spring(response: pressResponse, dampingFraction: 0.72)
    }

    static func revealSpring(reduced: Bool = false) -> Animation? {
        reduced ? .easeOut(duration: 0.12) : .spring(response: standardResponse, dampingFraction: 0.88)
    }

    static func sidebarSpring(reduced: Bool = false) -> Animation? {
        reduced ? .easeOut(duration: 0.10) : .spring(response: 0.22, dampingFraction: 0.90)
    }

    static func quickOrNone(reduced: Bool) -> Animation? {
        reduced ? nil : .easeOut(duration: 0.2)
    }

    static func standardOrNone(reduced: Bool) -> Animation? {
        reduced ? nil : .easeInOut(duration: standardResponse)
    }

    static func springOrEase(reduced: Bool) -> Animation? {
        reduced ? nil : .spring(response: 0.32, dampingFraction: 0.86)
    }
}

/// Combines system Reduce Motion with the in-app `ui.reduceMotion` preference.
enum CollegeReduceMotionGate {
    static func isReduced(accessibilityReduceMotion: Bool, appReduceMotion: Bool) -> Bool {
        accessibilityReduceMotion || appReduceMotion
    }
}
