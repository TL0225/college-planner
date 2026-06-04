// DesignSystem+Tokens.swift
// Feature: Core
// Purpose: Core module — Spacing.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

extension DesignSystem {
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 20
    }

    struct Radius {
        static let md: CGFloat = 12
    }

    enum Motion {
        static let cardHover: Animation = .easeOut(duration: 0.15)

        static func quickOrNone(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .easeOut(duration: 0.2)
        }

        static func standardOrNone(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .easeInOut(duration: 0.28)
        }

        static func springOrEase(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)
        }
    }
}

extension DesignSystem.Colors {
    static let tertiaryText = DesignSystem.Colors.textLight
    static let labelOnFilled = Color.white

    static let careerLaneInterested = Color(hex: "64748b")
    static let careerLaneApplied = Color(hex: "3b82f6")
    static let careerLaneInterviewing = Color(hex: "8b5cf6")
    static let careerLaneOffer = Color(hex: "f59e0b")
    static let careerLaneRejected = Color(hex: "ef4444")
    static let careerLaneAccepted = Color(hex: "10b981")
    static let careerCardBackground = DesignSystem.Colors.surface
    static let careerPayGreen = Color(hex: "16a34a")
}

extension DesignSystem.Fonts {
    static func headline(weight: Font.Weight = .semibold) -> Font {
        main(size: 17, weight: weight)
    }

    static func title1(weight: Font.Weight = .bold) -> Font {
        main(size: 22, weight: weight)
    }

    static func title2(weight: Font.Weight = .bold) -> Font {
        main(size: 20, weight: weight)
    }

    static func title3(weight: Font.Weight = .semibold) -> Font {
        main(size: 18, weight: weight)
    }

    static func body(weight: Font.Weight = .regular) -> Font {
        main(size: 15, weight: weight)
    }

    static func caption1(weight: Font.Weight = .regular) -> Font {
        main(size: 12, weight: weight)
    }

    static func caption2(weight: Font.Weight = .regular) -> Font {
        main(size: 11, weight: weight)
    }
}
