// BuildCompatibility.swift
// Feature: Core
// Purpose: Core module — BuildCompatibility.
// Data: CollegePersistence / repositories when applicable.

import Foundation

// MARK: - Notifications

extension Notification.Name {
    static let careerOpenAddApplication = Notification.Name("career.openAddApplication")
    static let careerOpenEditApplication = Notification.Name("career.openEditApplication")
    static let careerOpenBoardJob = Notification.Name("career.openBoardJob")
    static let careerFilterByStage = Notification.Name("career.filterByStage")
    static let calendarToolbarSetMode = Notification.Name("calendar.toolbar.setMode")
    static let catalogDataDidCommit = Notification.Name("catalog.dataDidCommit")
    static let catalogRequirementsDidUpdate = Notification.Name("catalog.requirementsDidUpdate")
    static let graduationPlanChanged = Notification.Name("graduationPlanChanged")
}
