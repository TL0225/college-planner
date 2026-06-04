// CalendarTimelineEpics.swift
// Feature: Calendar
// Purpose: Calendar module — CalendarEventDependency.
// Data: CollegePersistence / repositories when applicable.

import Foundation

// MARK: - Phase 8: dependency graph (foundation)

struct CalendarEventDependency: Codable, Identifiable, Equatable {
    var id: UUID
    var predecessorEventID: UUID
    var successorEventID: UUID
    var lagMinutes: Int
}

enum CalendarDependencyStore {
    private static let key = "calendar.dependencies.v1"

    static func load() -> [CalendarEventDependency] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([CalendarEventDependency].self, from: data)
        else { return [] }
        return items
    }
}

// MARK: - Phase 9: plan vs actual

enum CalendarDisplayMode: String, CaseIterable {
    case planned
    case actual
    case overlay
}

// MARK: - Phase 10: cognitive energy

struct CognitiveEnergyWindow: Codable, Equatable {
    var peakStartHour: Int
    var peakEndHour: Int
    var dailyCapacityScore: Double
}

// MARK: - Phase 11: conditional branching

struct ConditionalForkLane: Codable, Identifiable, Equatable {
    var id: UUID
    var triggerWebhookURL: String?
    var trueBranchEventID: UUID?
    var falseBranchEventID: UUID?
}
