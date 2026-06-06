// CalendarEditorPresentation.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarEditorPresentationKey.
// Data: CollegePersistence / repositories when applicable.

import SwiftUI

/// How the calendar event editor is presented (drives material / chrome).
enum CalendarEditorPresentation: Equatable {
    case gridPopover
    case sidebarSheet
    case anchoredPanel
    case fullScreenOverlay
}

private struct CalendarEditorPresentationKey: EnvironmentKey {
    static let defaultValue: CalendarEditorPresentation = .fullScreenOverlay
}

extension EnvironmentValues {
    var calendarEditorPresentation: CalendarEditorPresentation {
        get { self[CalendarEditorPresentationKey.self] }
        set { self[CalendarEditorPresentationKey.self] = newValue }
    }
}

extension View {
    func calendarEditorPresentation(_ value: CalendarEditorPresentation) -> some View {
        environment(\.calendarEditorPresentation, value)
    }
}
