// IntegrationStatusBadge.swift
// Feature: Core
// Purpose: Core module — IntegrationStatusBadge.
// Data: CollegePersistence / repositories when applicable.

import CollegePlatform
import SwiftUI

/// Connection-bar indicator for integration export/sync health.
struct IntegrationStatusBadge: View {
    let integrationID: IntegrationID
    @Bindable var healthStore: IntegrationHealthStore

    var body: some View {
        let snapshot = healthStore.snapshot(for: integrationID)
        Circle()
            .fill(snapshot.isFailure ? Color.red : Color.green.opacity(snapshot.lastOutcome == nil ? 0.35 : 0.9))
            .frame(width: 8, height: 8)
            .help(helpText(snapshot))
    }

    private func helpText(_ snapshot: IntegrationHealthSnapshot) -> String {
        switch snapshot.lastOutcome {
        case .exportFailure(let message):
            return "Export failed: \(message)"
        case .importFailure(let message):
            return "Import failed: \(message)"
        case .connectionLost:
            return "Connection lost"
        case .success:
            return "Synced"
        case .none:
            return "No recent activity"
        }
    }
}
