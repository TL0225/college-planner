// GlassToolbarEnvironment.swift
// Feature: App / Toolbar / Glass

import SwiftUI

private struct GlassToolbarStyleBox: @unchecked Sendable {
    var style: any GlassToolbarStyle
}

private struct GlassToolbarStyleKey: EnvironmentKey {
    static let defaultValue = GlassToolbarStyleBox(style: TahoeGlassStyle())
}

extension EnvironmentValues {
    var glassToolbarStyle: any GlassToolbarStyle {
        get { self[GlassToolbarStyleKey.self].style }
        set { self[GlassToolbarStyleKey.self].style = newValue }
    }
}

struct GlassToolbarEnvironmentModifier: ViewModifier {
    var density: ToolbarDensity

    func body(content: Content) -> some View {
        content
            .environment(\.glassToolbarStyle, TahoeGlassStyle())
            .environment(\.toolbarDensity, density)
    }
}

extension View {
    func glassToolbarEnvironment(density: ToolbarDensity) -> some View {
        modifier(GlassToolbarEnvironmentModifier(density: density))
    }
}
