// ToolbarMetrics.swift
// Feature: Core
// Purpose: Core module — ToolbarMetrics.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Shared sizing + typography for every in-app toolbar.
///
/// All toolbar text uses **SF Pro 12pt** (plain `.system`, not Rounded) so the title, controls,
/// pill labels, and filter chips read as one consistent strip across the app. Only weight varies.
enum ToolbarMetrics {
    static let pointSize: CGFloat = 12

    /// SF Pro 12pt at the requested weight.
    static func font(_ weight: Font.Weight) -> Font {
        .system(size: pointSize, weight: weight)
    }

    static let titleFont   = font(.semibold)
    static let controlFont = font(.semibold)
    static let iconFont    = font(.semibold)
    static let labelFont   = font(.medium)

    static let itemHorizontalPadding: CGFloat = 8
    static let itemSpacing: CGFloat = 12
}
