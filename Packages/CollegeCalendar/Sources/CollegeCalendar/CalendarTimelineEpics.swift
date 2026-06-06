import Foundation

// MARK: - Phase 8: dependency graph (foundation)

public struct CalendarStoredEventDependency: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var predecessorEventID: UUID
    public var successorEventID: UUID
    public var lagMinutes: Int

    public init(id: UUID, predecessorEventID: UUID, successorEventID: UUID, lagMinutes: Int) {
        self.id = id
        self.predecessorEventID = predecessorEventID
        self.successorEventID = successorEventID
        self.lagMinutes = lagMinutes
    }
}

public enum CalendarDependencyStore: Sendable {
    private static let key = "calendar.dependencies.v1"

    public static func load() -> [CalendarStoredEventDependency] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([CalendarStoredEventDependency].self, from: data)
        else { return [] }
        return items
    }
}

// MARK: - Phase 9: plan vs actual

public enum CalendarDisplayMode: String, CaseIterable, Sendable {
    case planned
    case actual
    case overlay
}

// MARK: - Phase 10: cognitive energy

public struct CognitiveEnergyWindow: Codable, Equatable, Sendable {
    public var peakStartHour: Int
    public var peakEndHour: Int
    public var dailyCapacityScore: Double

    public init(peakStartHour: Int, peakEndHour: Int, dailyCapacityScore: Double) {
        self.peakStartHour = peakStartHour
        self.peakEndHour = peakEndHour
        self.dailyCapacityScore = dailyCapacityScore
    }
}

// MARK: - Phase 11: conditional branching

public struct ConditionalForkLane: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var triggerWebhookURL: String?
    public var trueBranchEventID: UUID?
    public var falseBranchEventID: UUID?

    public init(
        id: UUID,
        triggerWebhookURL: String? = nil,
        trueBranchEventID: UUID? = nil,
        falseBranchEventID: UUID? = nil
    ) {
        self.id = id
        self.triggerWebhookURL = triggerWebhookURL
        self.trueBranchEventID = trueBranchEventID
        self.falseBranchEventID = falseBranchEventID
    }
}
