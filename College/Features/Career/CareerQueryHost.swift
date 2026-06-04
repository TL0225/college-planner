// CareerQueryHost.swift
// Feature: Career
// Purpose: Career module — CareerQueryHost.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import SwiftUI

/// Invalidates career UI when local store job-application rows change (Phase 7e).
struct CareerQueryHost: View {
    @Query(sort: [SortDescriptor(\JobApplication.sortOrder, order: .forward)])
    private var applications: [JobApplication]

    let onApplicationsChange: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                publishChange()
            }
            .onChange(of: applications.count) { _, _ in publishChange() }
    }

    private func publishChange() {
        onApplicationsChange()
    }
}
