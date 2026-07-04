// CalendarInspectorLayout.swift
// Feature: Calendar
// Purpose: Layout rules for the embedded event inspector sidebar.

import Foundation

public enum CalendarInspectorLayout {
    /// The duplicate extras card is omitted in inspector mode.
    public static func showsExtrasCard(isInspectorEmbedded: Bool) -> Bool {
        !isInspectorEmbedded
    }
}
