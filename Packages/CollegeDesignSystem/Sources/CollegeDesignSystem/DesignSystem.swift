import AppKit
import SwiftUI

public struct DesignSystem {
    public struct Colors {
        /// Loads an adaptive named color from the design system Asset Catalog,
        /// falling back to a constant hex value if the asset is unavailable.
        static func named(_ name: String, fallback hex: String) -> Color {
            #if canImport(AppKit)
            if NSColor(named: name, bundle: .module) != nil {
                return Color(name, bundle: .module)
            }
            #endif
            return Color(hex: hex)
        }

        public static let primary = named("Primary", fallback: "6366f1")
        public static let secondary = named("Secondary", fallback: "a855f7")
        public static let accent = named("Accent", fallback: "ec4899")
        public static let success = named("Success", fallback: "10b981")
        public static let warning = named("Warning", fallback: "f59e0b")
        public static let error = named("Error", fallback: "ef4444")
        public static let info = named("Info", fallback: "06b6d4")
        public static let bgMain: Color = Color(nsColor: .windowBackgroundColor)
        public static let surface: Color = Color(nsColor: .controlBackgroundColor)
        public static let textMain: Color = Color(nsColor: .labelColor)
        public static let textLight: Color = Color(nsColor: .secondaryLabelColor)
        public static let sidebarSelection: Color = Color(nsColor: .controlAccentColor)
        // Accent-based (not `selectedContentBackgroundColor`) so the selection keeps its
        // tint when the window is inactive instead of desaturating to system gray.
        public static let sidebarSelectionFill: Color = Color(nsColor: .controlAccentColor).opacity(0.22)
        public static let sidebarHoverFill: Color = Color(nsColor: .controlAccentColor).opacity(0.10)
        public static let chromeStroke: Color = Color(nsColor: .separatorColor).opacity(0.55)
        public static let glassCardBase: Color = Color(nsColor: .windowBackgroundColor).opacity(0.72)
    }

    public struct Fonts {
        public static func main(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .rounded) -> Font {
            .system(size: size, weight: weight, design: design)
        }
    }
}

public extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    func hexRGBString() -> String? {
        let nsColor = NSColor(self)
        guard let rgb = nsColor.usingColorSpace(.deviceRGB) else { return nil }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "%02x%02x%02x", r, g, b)
    }
}
