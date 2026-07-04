// ToolbarAction.swift
// Feature: App / Toolbar
// Purpose: Versioned toolbar action API surface with per-feature ownership.

import CollegeCalendar
import Foundation

// Owner: AcademicsView — College/Features/Academics/AcademicsView.swift
enum AcademicsToolbarAction: Sendable, Equatable {
    case statsSidebarToggle
    case addCourse
}

// Owner: WebPortalSceneState hosts — ShortcutWebHostView, LMSView
enum WebToolbarAction: Sendable, Equatable {
    case back
    case forward
    case reload
    case portalHome
    case findInPage
}

// Owner: CareerWorkspaceView — College/Features/Career/Workspace/CareerWorkspaceView.swift
enum CareerToolbarAction: Sendable, Equatable {
    case addApplication
    case copyBoardMarkdown
}

// Owner: TransferDatabaseView — College/Features/Transfer
enum TransferToolbarAction: Sendable, Equatable {
    case refreshOfficial
    case importCommunity
    case addManualEntry
    case shareToCommunity
    case toggleMode
}

// Owner: AIAssistantView — College/Features/Assistant/AIAssistantView.swift
enum AssistantToolbarAction: Sendable, Equatable {
    case openWebMemory
    case regenerateLastReply
    case exportTranscript
    case clearThread
}

// Owner: ProfileView — College/Features/Profile/ProfileView.swift
enum ProfileToolbarAction: Sendable, Equatable {
    case advisorPrep
    case editProfile
}

enum ToolbarAction: Sendable, Equatable {
    case calendar(CalendarToolbarAction)
    case academics(AcademicsToolbarAction)
    case web(WebToolbarAction)
    case career(CareerToolbarAction)
    case transfer(TransferToolbarAction)
    case assistant(AssistantToolbarAction)
    case profile(ProfileToolbarAction)
}

enum ToolbarHandlerOwner: Hashable, Sendable {
    case calendar
    case academics
    case webPortal(UUID?)
    case career
    case transfer
    case assistant
    case profile
}
