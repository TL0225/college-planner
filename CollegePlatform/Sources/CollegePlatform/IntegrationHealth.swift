import Foundation
import Observation

public enum IntegrationID: String, Sendable, Codable, CaseIterable {
    case google
    case apple
    case outlook
    case icloud
    case lms
    case catalog
}

public enum IntegrationOutcome: Sendable, Equatable {
    case success
    case exportFailure(String)
    case importFailure(String)
    case connectionLost
}

public struct IntegrationHealthSnapshot: Sendable, Equatable {
    public var lastOutcome: IntegrationOutcome?
    public var updatedAt: Date?

    public var isFailure: Bool {
        switch lastOutcome {
        case .exportFailure, .importFailure, .connectionLost:
            return true
        case .success, .none:
            return false
        }
    }

    public init(lastOutcome: IntegrationOutcome? = nil, updatedAt: Date? = nil) {
        self.lastOutcome = lastOutcome
        self.updatedAt = updatedAt
    }
}

/// Tracks last-known export/sync health for integration connection indicators.
@MainActor
@Observable
public final class IntegrationHealthStore {
    public static let shared = IntegrationHealthStore()

    private var snapshots: [IntegrationID: IntegrationHealthSnapshot] = [:]

    public init() {}

    public func report(_ integration: IntegrationID, _ outcome: IntegrationOutcome) {
        snapshots[integration] = IntegrationHealthSnapshot(lastOutcome: outcome, updatedAt: .now)
    }

    public func snapshot(for integration: IntegrationID) -> IntegrationHealthSnapshot {
        snapshots[integration] ?? IntegrationHealthSnapshot()
    }

    public func resetAll() {
        snapshots.removeAll()
    }
}
