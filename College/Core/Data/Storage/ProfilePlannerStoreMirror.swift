// ProfilePlannerStoreMirror.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — ProfilePlannerStoreMirror.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Deprecated dual-write shim (Phase 7f). local store is authoritative; upserts are no-ops.
enum ProfilePlannerStoreMirror {
    static func upsertPlan(_ entity: Any) { _ = entity }
    static func deletePlan(id: UUID) { deletePlanID(id) }
    static func upsertSemester(_ entity: Any) { _ = entity }
    static func deleteSemester(id: UUID) { deleteSemesterID(id) }
    static func upsertCourse(_ entity: Any) { _ = entity }
    static func deleteCourse(id: UUID) { deleteCourseID(id) }
    static func upsertCalendarEvent(_ entity: Any) { _ = entity }
    static func deleteCalendarEvent(id: UUID) { deleteCalendarEventID(id) }
    static func upsertPlannerTask(_ entity: Any) { _ = entity }
    static func deletePlannerTask(id: UUID) { deletePlannerTaskID(id) }
    static func upsertProfile(_ entity: Any) { _ = entity }
    static func upsertAcademicProfile(_ entity: Any) { _ = entity }
    static func deleteAcademicProfile(id: UUID) { deleteAcademicProfileID(id) }

    static func flushPendingWrites() {
        onMain {
            ModelMergeCoalescer.flushNow()
            AppDataStore.shared.bumpProfileRevision()
        }
    }

    static func performOnMainActor(_ work: @escaping @MainActor () -> Void) {
        Task { @MainActor in work() }
    }

    static func mirrorPlanAfterSave(objectID: Any) { _ = objectID }
    static func mirrorSemesterAfterSave(objectID: Any) { _ = objectID }
    static func mirrorCourseAfterSave(objectID: Any) { _ = objectID }
    static func mirrorCalendarEventAfterSave(objectID: Any) { _ = objectID }
    static func mirrorPlannerTaskAfterSave(objectID: Any) { _ = objectID }
    static func mirrorProfileAfterSave(_ entity: Any) { _ = entity }
    static func mirrorAcademicProfileAfterSave(_ entity: Any) { _ = entity }
    static func mirrorProfileAfterSave(objectID: Any) { _ = objectID }
    static func mirrorAcademicProfileAfterSave(objectID: Any) { _ = objectID }

    private static func deletePlanID(_ id: UUID) {
        onMain {
            try? AppDataStore.shared.profileRepository.deletePlan(id: id)
            ModelMergeCoalescer.flushNow()
            AppDataStore.shared.bumpProfileRevision()
        }
    }

    private static func deleteSemesterID(_ id: UUID) {
        onMain {
            try? AppDataStore.shared.profileRepository.deleteSemester(id: id)
            ModelMergeCoalescer.flushNow()
            AppDataStore.shared.bumpProfileRevision()
        }
    }

    private static func deleteCourseID(_ id: UUID) {
        onMain {
            try? AppDataStore.shared.profileRepository.deleteCourse(id: id)
            ModelMergeCoalescer.flushNow()
            AppDataStore.shared.bumpProfileRevision()
        }
    }

    private static func deleteCalendarEventID(_ id: UUID) {
        onMain {
            try? AppDataStore.shared.calendarRepository.deleteCalendarEvent(id: id)
            ModelMergeCoalescer.flushNow()
            AppDataStore.shared.bumpProfileRevision()
        }
    }

    private static func deletePlannerTaskID(_ id: UUID) {
        onMain {
            try? AppDataStore.shared.calendarRepository.deletePlannerTask(id: id)
            ModelMergeCoalescer.flushNow()
            AppDataStore.shared.bumpProfileRevision()
        }
    }

    private static func deleteAcademicProfileID(_ id: UUID) {
        onMain {
            try? AppDataStore.shared.profileRepository.deleteAcademicProfile(id: id)
            ModelMergeCoalescer.flushNow()
            AppDataStore.shared.bumpProfileRevision()
        }
    }

    private static func onMain(_ work: @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { work() }
        } else {
            DispatchQueue.main.sync { work() }
        }
    }
}