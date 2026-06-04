// OverviewQueryHost.swift
// Feature: Overview
// Purpose: Overview module — OverviewQueryHost.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import SwiftUI

/// Invalidates overview widgets when local store profile partition rows change (Phase 7e).
struct OverviewQueryHost: View {
    @Query(sort: [SortDescriptor(\PlannerTask.dueDate, order: .forward)])
    private var plannerTasks: [PlannerTask]

    @Query(sort: [SortDescriptor(\CalendarEvent.startDate, order: .forward)])
    private var calendarEvents: [CalendarEvent]

    @Query(sort: [SortDescriptor(\JobApplication.sortOrder, order: .forward)])
    private var careerApplications: [JobApplication]

    @Query(sort: [SortDescriptor(\AcademicProfile.sortOrder, order: .forward)])
    private var academicProfiles: [AcademicProfile]

    @Query(sort: [SortDescriptor(\VaultDocument.addedAt, order: .reverse)])
    private var vaultDocuments: [VaultDocument]

    let onDataChange: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                publishChange()
            }
            .onChange(of: plannerTasks.count) { _, _ in publishChange() }
            .onChange(of: calendarEvents.count) { _, _ in publishChange() }
            .onChange(of: careerApplications.count) { _, _ in publishChange() }
            .onChange(of: academicProfiles.count) { _, _ in publishChange() }
            .onChange(of: vaultDocuments.count) { _, _ in publishChange() }
    }

    private func publishChange() {
        onDataChange()
    }
}
