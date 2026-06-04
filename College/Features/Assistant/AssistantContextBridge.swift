// AssistantContextBridge.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantContextBridge.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// Bounded local store reads for assistant title matching (Phase 7f).
@MainActor
enum AssistantContextBridge {
    static func boundedCalendarEvents(
        collegePersistence: CollegePersistence,
        limit: Int = 300
    ) -> [CalendarEvent] {
        let cap = max(1, min(limit, 500))
        let start = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        let end = Calendar.current.date(byAdding: .year, value: 2, to: Date()) ?? Date()
        return (try? collegePersistence.calendarRepository.fetchEvents(from: start, to: end, limit: cap)) ?? []
    }

    static func boundedPlannerTasks(
        collegePersistence: CollegePersistence,
        limit: Int = 300
    ) -> [PlannerTask] {
        let cap = max(1, min(limit, 500))
        let horizon = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        return (try? collegePersistence.calendarRepository.fetchTasks(dueBefore: horizon, limit: cap)) ?? []
    }
}
