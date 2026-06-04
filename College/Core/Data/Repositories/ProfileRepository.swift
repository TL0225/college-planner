// ProfileRepository.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — ProfileRepository.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// Bounded local store fetch helpers for the profile partition (Phase 7b).
@MainActor
struct ProfileRepository {
    let context: ModelContext

    func fetchPlans(limit: Int = 100) throws -> [PlannerPlan] {
        var descriptor = FetchDescriptor<PlannerPlan>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = max(1, limit)
        return try context.fetch(descriptor)
    }

    func fetchPlan(id: UUID) throws -> PlannerPlan? {
        var descriptor = FetchDescriptor<PlannerPlan>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchSemesters(limit: Int = 120) throws -> [PlannerSemester] {
        var descriptor = FetchDescriptor<PlannerSemester>(
            sortBy: [
                SortDescriptor(\.year, order: .forward),
                SortDescriptor(\.seasonOrder, order: .forward),
            ]
        )
        descriptor.fetchLimit = max(1, limit)
        return try context.fetch(descriptor)
    }

    func fetchSemester(id: UUID) throws -> PlannerSemester? {
        var descriptor = FetchDescriptor<PlannerSemester>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchSemesters(forPlanID planID: UUID, limit: Int = 60) throws -> [PlannerSemester] {
        var descriptor = FetchDescriptor<PlannerSemester>(
            predicate: #Predicate { semester in
                semester.plan?.id == planID
            },
            sortBy: [
                SortDescriptor(\.year, order: .forward),
                SortDescriptor(\.seasonOrder, order: .forward),
            ]
        )
        descriptor.fetchLimit = max(1, limit)
        return try context.fetch(descriptor)
    }

    func fetchCourses(forSemesterID semesterID: UUID, limit: Int = 80) throws -> [PlannerCourse] {
        var descriptor = FetchDescriptor<PlannerCourse>(
            predicate: #Predicate { course in
                course.semester?.id == semesterID
            },
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        descriptor.fetchLimit = max(1, limit)
        return try context.fetch(descriptor)
    }

    func fetchCourse(id: UUID) throws -> PlannerCourse? {
        var descriptor = FetchDescriptor<PlannerCourse>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchProfiles(limit: Int = 20) throws -> [Profile] {
        var descriptor = FetchDescriptor<Profile>()
        descriptor.fetchLimit = max(1, limit)
        return try context.fetch(descriptor)
    }

    func fetchPrimaryProfile() throws -> Profile? {
        var descriptor = FetchDescriptor<Profile>()
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchProfile(id: UUID) throws -> Profile? {
        var descriptor = FetchDescriptor<Profile>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchAcademicProfiles(limit: Int = 20) throws -> [AcademicProfile] {
        var descriptor = FetchDescriptor<AcademicProfile>(
            sortBy: [SortDescriptor(\.sortOrder, order: .forward)]
        )
        descriptor.fetchLimit = max(1, limit)
        return try context.fetch(descriptor)
    }

    func fetchAcademicProfile(id: UUID) throws -> AcademicProfile? {
        var descriptor = FetchDescriptor<AcademicProfile>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchPrimaryAcademicProfile() throws -> AcademicProfile? {
        var descriptor = FetchDescriptor<AcademicProfile>(
            predicate: #Predicate { $0.isPrimary == true && $0.isActive == true }
        )
        descriptor.fetchLimit = 1
        if let primary = try context.fetch(descriptor).first {
            return primary
        }
        return try fetchAcademicProfiles(limit: 1).first
    }

    func hasMirroredAcademicProfileRows() throws -> Bool {
        var descriptor = FetchDescriptor<AcademicProfile>()
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
    }
}