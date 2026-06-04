// AddCalendarItemOverlaySizing.swift
// Feature: Calendar
// Purpose: Calendar module — AddCalendarItemOverlayPreferredHeightKey.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

struct AddCalendarItemOverlayPreferredHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct AddTaskOverlayPreferredHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
