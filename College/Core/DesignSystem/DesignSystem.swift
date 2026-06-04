// DesignSystem.swift
// Feature: Core
// Purpose: Core module — DesignSystem.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI
import AppKit

struct DesignSystem {
    struct Colors {
        static let primary = Color(hex: "6366f1")   // Indigo
        static let secondary = Color(hex: "a855f7") // Purple
        static let accent = Color(hex: "ec4899")    // Pink
        static let success = Color(hex: "10b981")   // Emerald
        static let warning = Color(hex: "f59e0b")   // Amber
        static let error = Color(hex: "ef4444")     // Red
        static let info = Color(hex: "06b6d4")      // Cyan
        static let bgMain: Color = {
            return Color(nsColor: .windowBackgroundColor)
        }()
        static let surface: Color = {
            return Color(nsColor: .controlBackgroundColor)
        }()
        static let textMain: Color = {
            return Color(nsColor: .labelColor)
        }()
        static let textLight: Color = {
            return Color(nsColor: .secondaryLabelColor)
        }()

        static let sidebarSelection: Color = {
            return Color(nsColor: .controlAccentColor)
        }()

        static let sidebarSelectionFill: Color = {
            return Color(nsColor: .selectedContentBackgroundColor).opacity(0.22)
        }()

        static let sidebarHoverFill: Color = {
            return Color(nsColor: .controlAccentColor).opacity(0.10)
        }()

        static let chromeStroke: Color = {
            return Color(nsColor: .separatorColor).opacity(0.55)
        }()

        static let glassCardBase: Color = {
            return Color(nsColor: .windowBackgroundColor).opacity(0.72)
        }()
    }
    
    struct Fonts {
        static func main(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .rounded) -> Font {
            return .system(size: size, weight: weight, design: design)
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
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
