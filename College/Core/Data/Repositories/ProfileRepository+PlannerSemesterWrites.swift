// ProfileRepository+PlannerSemesterWrites.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — ProfileRepository+PlannerSemesterWrites.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension ProfileRepository {
    func updateSemesterDetails(id: UUID, season: String, year: Int) throws {
        guard let semester = try fetchSemester(id: id) else { return }
        semester.season = season
        semester.year = Int16(year)
        semester.seasonOrder = seasonOrder(for: season)
        semester.name = "\(season) \(year)"
        ModelMergeCoalescer.scheduleSave(context)
    }
}