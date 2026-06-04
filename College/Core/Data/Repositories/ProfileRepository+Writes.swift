// ProfileRepository+Writes.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — ProfileRepositoryWriteError.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

// MARK: - Phase 7f planner/profile deletes (local store-native writes live in ProfileRepository+NativeWrites)

extension ProfileRepository {
    func deletePlan(id: UUID) throws {
        guard let plan = try fetchPlan(id: id) else { return }
        context.delete(plan)
        ModelMergeCoalescer.scheduleSave(context)
    }

    func deleteSemester(id: UUID) throws {
        guard let semester = try fetchSemester(id: id) else { return }
        context.delete(semester)
        ModelMergeCoalescer.scheduleSave(context)
    }

    func deleteCourse(id: UUID) throws {
        guard let course = try fetchCourse(id: id) else { return }
        context.delete(course)
        ModelMergeCoalescer.scheduleSave(context)
    }

    /// Merges duplicate planner courses per semester (same base code); keeps the best row.
    func mergeCourseDuplicates() throws {
        let semesters = try fetchSemesters(limit: 500)
        var didChange = false

        for semester in semesters {
            let courses = try fetchCourses(forSemesterID: semester.id, limit: 500)
            var groups: [String: [PlannerCourse]] = [:]
            for course in courses {
                let base = baseCode(for: course.code)
                groups[base, default: []].append(course)
            }

            for group in groups.values where group.count > 1 {
                let winner = group.sorted { lhs, rhs in
                    if (lhs.catalogCourseID != nil) != (rhs.catalogCourseID != nil) {
                        return lhs.catalogCourseID != nil
                    }
                    if lhs.autoLinked != rhs.autoLinked { return !lhs.autoLinked }
                    return lhs.name.count > rhs.name.count
                }.first!

                for loser in group where loser.id != winner.id {
                    if let events = loser.calendarEvents {
                        for event in events { event.course = winner }
                    }
                    if !loser.autoLinked { winner.autoLinked = false }
                    context.delete(loser)
                    didChange = true
                }
            }
        }

        if didChange {
            ModelMergeCoalescer.scheduleSave(context)
        }
    }

    private func baseCode(for code: String) -> String {
        let compact = code.replacingOccurrences(of: " ", with: "").uppercased()
        var result = ""
        var seenDigit = false
        for character in compact {
            if character.isNumber {
                seenDigit = true
                result.append(character)
            } else if seenDigit {
                break
            } else {
                result.append(character)
            }
        }
        return result
    }

    func deleteAcademicProfile(id: UUID) throws {
        guard let academic = try fetchAcademicProfile(id: id) else { return }
        context.delete(academic)
        ModelMergeCoalescer.scheduleSave(context)
    }
}

enum ProfileRepositoryWriteError: Error {
    case missingSemesterForCourse
}