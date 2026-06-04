import Foundation
import Observation

public enum IntegrationID: String, Sendable, CaseIterable {
    case apple
    case google
    case outlook
    case icloud
    case brightspace
}

public enum IntegrationSyncOutcome: Sendable, Equatable {
    case success
    case exportFailure(String)
    case importFailure(String)
    case connectionLost
}

public struct IntegrationHealthSnapshot: Sendable, Equatable {
    public var lastOutcome: IntegrationSyncOutcome?
    public var lastUpdated: Date

    public init(lastOutcome: IntegrationSyncOutcome? = nil, lastUpdated: Date = .distantPast) {
        self.lastOutcome = lastOutcome
        self.lastUpdated = lastUpdated
    }

    public var isFailure: Bool {
        switch lastOutcome {
        case .exportFailure, .importFailure, .connectionLost:
            return true
        case .success, .none:
            return false
        }
    }
}

@Observable
public final class IntegrationHealthStore {
    public private(set) var snapshot: [IntegrationID: IntegrationHealthSnapshot] = [:]

    public init() {}

    public func report(_ id: IntegrationID, _ outcome: IntegrationSyncOutcome) {
        snapshot[id] = IntegrationHealthSnapshot(lastOutcome: outcome, lastUpdated: Date())
    }

    public func snapshot(for id: IntegrationID) -> IntegrationHealthSnapshot {
        snapshot[id] ?? IntegrationHealthSnapshot()
    }
}
