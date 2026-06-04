// AcademicsSemesterQueryHost.swift
// Feature: Academics
// Purpose: Academics module — AcademicsSemesterQueryHost.
// Data: CollegePersistence / repositories when applicable.

import SwiftData
import SwiftUI

/// Hosts `@Query` for planner semesters (Phase 7e); used to invalidate Academics when local store changes.
struct AcademicsSemesterQueryHost: View {
    @Query(
        sort: [
            SortDescriptor(\PlannerSemester.year, order: .reverse),
            SortDescriptor(\PlannerSemester.seasonOrder, order: .reverse),
        ]
    )
    private var plannerSemesters: [PlannerSemester]

    let onSemesterCountChange: (Int) -> Void
    let onPlannerSemestersChange: ([PlannerSemester]) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { publish() }
            .onChange(of: plannerSemesters.count) { _, _ in publish() }
    }

    private func publish() {
        let courseCount = plannerSemesters.reduce(0) { partial, semester in
            partial + (semester.courses?.count ?? 0)
        }
        onSemesterCountChange(courseCount)
        onPlannerSemestersChange(plannerSemesters)
    }
}
