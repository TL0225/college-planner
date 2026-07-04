import SwiftUI

public extension DesignSystem {
    struct Spacing {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 20
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
        public static let section: CGFloat = 40
    }

    struct Radius {
        public static let sm: CGFloat = 6
        public static let md: CGFloat = 10
        public static let lg: CGFloat = 14
        public static let xl: CGFloat = 20
        public static let sheet: CGFloat = 24
    }

    enum Materials {
        case thin
        case ultraThin
        case regular

        public var material: Material {
            switch self {
            case .thin: .thinMaterial
            case .ultraThin: .ultraThinMaterial
            case .regular: .regularMaterial
            }
        }
    }

    enum Motion {
        public static let cardHover: Animation = .easeOut(duration: 0.15)
        public static let maxDuration: TimeInterval = 0.4

        public static func quickOrNone(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .easeOut(duration: 0.2)
        }

        public static func standardOrNone(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .easeInOut(duration: 0.28)
        }

        public static func springOrEase(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)
        }
    }
}

public extension DesignSystem.Colors {
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

public extension DesignSystem.Fonts {
    static func headline(weight: Font.Weight = .semibold) -> Font {
        .headline.weight(weight)
    }

    static func title1(weight: Font.Weight = .bold) -> Font {
        .title.weight(weight)
    }

    static func title2(weight: Font.Weight = .bold) -> Font {
        .title2.weight(weight)
    }

    static func title3(weight: Font.Weight = .semibold) -> Font {
        .title3.weight(weight)
    }

    static func body(weight: Font.Weight = .regular) -> Font {
        .body.weight(weight)
    }

    static func caption1(weight: Font.Weight = .regular) -> Font {
        .caption.weight(weight)
    }

    static func caption2(weight: Font.Weight = .regular) -> Font {
        .caption2.weight(weight)
    }

    /// Display-only rounded treatment (logos, hero numerals).
    static func display(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        main(size: size, weight: weight, design: .rounded)
    }
}
