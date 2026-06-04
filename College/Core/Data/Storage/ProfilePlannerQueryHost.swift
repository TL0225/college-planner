// ProfilePlannerQueryHost.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — ProfilePlannerQueryHost.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import SwiftUI

/// Invalidates planner/profile UI when local store planner rows change (Phase 7e).
struct ProfilePlannerQueryHost: View {
    @Query(sort: [SortDescriptor(\PlannerPlan.createdAt, order: .forward)])
    private var plans: [PlannerPlan]

    @Query private var profiles: [Profile]

    let onPlannerChange: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                Task { @MainActor in
                    publishChange()
                }
            }
            .onChange(of: plans.count) { _, _ in publishChange() }
            .onChange(of: profiles.count) { _, _ in publishChange() }
    }

    private func publishChange() {
        Task { @MainActor in
            onPlannerChange()
        }
    }
}