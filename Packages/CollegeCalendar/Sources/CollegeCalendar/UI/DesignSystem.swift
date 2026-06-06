import AppKit
import SwiftUI

struct DesignSystem {
    struct Colors {
        static let primary = Color(hex: "6366f1")
        static let secondary = Color(hex: "a855f7")
        static let accent = Color(hex: "ec4899")
        static let success = Color(hex: "10b981")
        static let warning = Color(hex: "f59e0b")
        static let error = Color(hex: "ef4444")
        static let info = Color(hex: "06b6d4")
        static let bgMain: Color = Color(nsColor: .windowBackgroundColor)
        static let surface: Color = Color(nsColor: .controlBackgroundColor)
        static let textMain: Color = Color(nsColor: .labelColor)
        static let textLight: Color = Color(nsColor: .secondaryLabelColor)
        static let sidebarSelection: Color = Color(nsColor: .controlAccentColor)
        static let sidebarSelectionFill: Color = Color(nsColor: .selectedContentBackgroundColor).opacity(0.22)
        static let sidebarHoverFill: Color = Color(nsColor: .controlAccentColor).opacity(0.10)
        static let chromeStroke: Color = Color(nsColor: .separatorColor).opacity(0.55)
        static let glassCardBase: Color = Color(nsColor: .windowBackgroundColor).opacity(0.72)
    }

    struct Fonts {
        static func main(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .rounded) -> Font {
            .system(size: size, weight: weight, design: design)
        }
    }
}
