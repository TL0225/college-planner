// CalendarToolbarState.swift
// Feature: App
// Purpose: App module — CalendarToolbarState.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import Observation

/// Calendar tab toolbar display state (actions use `Notification.Name.calendarToolbar*`).
@Observable
@MainActor
final class CalendarToolbarState {
    var headerDate: String = ""
    var viewMode: CalendarViewDisplayMode = .month
    var sidebarShown: Bool = true
    var sidebarPanel: CalendarSidebarPanel = .eventList

    func requestMode(_ mode: CalendarViewDisplayMode) {
        viewMode = mode
        NotificationCenter.default.post(name: .calendarToolbarSetMode, object: mode)
    }
}
