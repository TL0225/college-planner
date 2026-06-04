// DebugLogModifiers.swift
// Feature: Debug
// Purpose: Debug module — DebugLogModifiers.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// Lightweight SwiftUI helpers to automatically log common UI interactions.
///
/// Goals:
/// - Make it easy to log button taps + screen appearances without cluttering view code.
/// - Keep the logging dependency minimal (just `DebugLogger`).
///
/// Usage examples:
/// - Button("Import") { ... }.debugLogTap("Import Catalog")
/// - SomeView().debugLogScreen("Academic Identity")
extension View {
    /// Logs a screen/view appearance.
    func debugLogScreen(_ name: String, file: String = #fileID, function: String = #function, line: Int = #line) -> some View {
        self.onAppear {
            DebugLogger.shared.nav("Screen appear: \(name)", file: file, function: function, line: line)
        }
    }

    /// Logs a generic UI tap attached to this view (useful for non-Button tappable controls).
    func debugLogTapGesture(_ name: String, file: String = #fileID, function: String = #function, line: Int = #line) -> some View {
        self.simultaneousGesture(
            TapGesture().onEnded {
                DebugLogger.shared.ui("Tap: \(name)", file: file, function: function, line: line)
            }
        )
    }
}

extension Button {
    /// Logs a button tap without changing the button's action.
    func debugLogTap(_ name: String, file: String = #fileID, function: String = #function, line: Int = #line) -> some View {
        self.simultaneousGesture(
            TapGesture().onEnded {
                DebugLogger.shared.ui("Button: \(name)", file: file, function: function, line: line)
            }
        )
    }
}
