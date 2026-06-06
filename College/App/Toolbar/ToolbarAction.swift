// ToolbarAction.swift
// Feature: App / Toolbar
// Purpose: Versioned toolbar action API surface with per-feature ownership.

import Foundation

// Owner: CalendarView — College/Features/Calendar/CalendarView.swift
enum CalendarToolbarAction: Sendable, Equatable {
    case previous
    case next
    case modeChange(CalendarViewDisplayMode)
    case sidebarToggle
    case sidebarPanelChange(CalendarSidebarPanel)
}

// Owner: AcademicsView — College/Features/Academics/AcademicsView.swift
enum AcademicsToolbarAction: Sendable, Equatable {
    case statsSidebarToggle
    case addCourse
}

// Owner: WebPortalSceneState hosts — ShortcutWebHostView, BrightspaceView
enum WebToolbarAction: Sendable, Equatable {
    case back
    case forward
    case reload
    case portalHome
    case findInPage
}

// Owner: CareerWorkspaceView — College/Features/Career/CareerWorkspaceView.swift
enum CareerToolbarAction: Sendable, Equatable {
    case addApplication
    case copyBoardMarkdown
}

enum ToolbarAction: Sendable, Equatable {
    case calendar(CalendarToolbarAction)
    case academics(AcademicsToolbarAction)
    case web(WebToolbarAction)
    case career(CareerToolbarAction)
}

enum ToolbarHandlerOwner: Hashable, Sendable {
    case calendar
    case academics
    case webPortal(UUID?)
    case career
    case assistant
}
