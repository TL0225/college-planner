// PlannerNarrativeService.swift
// Feature: Core
// Purpose: Core module — DaySummary.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Phase 7: template narrative for overview / assistant surfaces.
actor PlannerNarrativeService {
    struct DaySummary: Sendable {
        var date: Date
        var eventCount: Int
        var taskCount: Int
    }

    func narrative(for days: [DaySummary]) -> String {
        guard !days.isEmpty else { return "No upcoming calendar activity." }
        let totalEvents = days.reduce(0) { $0 + $1.eventCount }
        let totalTasks = days.reduce(0) { $0 + $1.taskCount }
        return "You have \(totalEvents) events and \(totalTasks) tasks across the next \(days.count) days."
    }
}
