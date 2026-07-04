// WidgetDescriptor.swift
// Feature: Overview
// Purpose: Overview module — in.
// Data: CollegePersistence / repositories when applicable.

//
//  WidgetDescriptor.swift
//  College
//
//  Closure-based widget definition.  Register instances in WidgetRegistry
//  to make them available in the Overview and the Widget Picker.
//

import SwiftUI

// MARK: - WidgetCategory

/// Groups widgets inside the picker's filter pills.
enum WidgetCategory: String, CaseIterable, Identifiable {
    case academic     = "Academic"
    case productivity = "Productivity"
    case media        = "Media"
    case information  = "Information"
    case custom       = "Custom"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .academic:     return "graduationcap.fill"
        case .productivity: return "checkmark.circle.fill"
        case .media:        return "music.note"
        case .information:  return "info.circle.fill"
        case .custom:       return "puzzlepiece.fill"
        }
    }

    /// Canonical accent color for the category. Overview widget headers bind their
    /// accent to this so header color encodes *domain* (academic vs productivity vs …)
    /// rather than being a per-widget decorative choice.
    var accentColor: Color {
        switch self {
        case .academic:     return .accentColor
        case .productivity: return .orange
        case .media:        return .pink
        case .information:  return .teal
        case .custom:       return .indigo
        }
    }
}

// MARK: - WidgetSize

/// Suggested size tiers a widget can declare it supports.
enum WidgetSize: String, CaseIterable {
    case small  = "Small"
    case medium = "Medium"
    case large  = "Large"
}

// MARK: - WidgetDescriptor

/// A self-describing, closure-based widget definition.
///
/// **Adding a new widget** (3 steps):
/// 1. Create a SwiftUI `View` struct in `College/Overview/Widgets/`.
/// 2. Add a `static var descriptor: WidgetDescriptor` computed property on the view,
///    filling in `makePreview`.
/// 3. Call `WidgetRegistry.shared.register(YourWidget.descriptor)` from
///    `WidgetRegistry.bootstrapBuiltIns()` (or anywhere before the Overview renders).
struct WidgetDescriptor: Identifiable {
    /// Stable string key used for persistence.  **Never change this after shipping.**
    let id: String

    let displayName: String
    let description: String
    let category: WidgetCategory

    /// SF Symbol name shown as the picker tile icon.
    let iconName: String
    let accentColor: Color

    let defaultHeight: CGFloat
    let minHeight: CGFloat

    /// Builds a **static, non-interactive** preview for the Widget Picker.
    /// Must NOT use environment objects, local store or live services —
    /// use hard-coded mock data so the picker renders instantly without
    /// triggering permission prompts.
    let makePreview: () -> any View
}
