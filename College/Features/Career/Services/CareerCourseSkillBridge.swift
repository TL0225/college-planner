// CareerCourseSkillBridge.swift
// Feature: Career
// Purpose: Map missing job skills to planner courses from the student's catalog.

import Foundation
import CollegeCareer

enum CareerCourseSkillBridge {
    @MainActor
    static func gaps(for missingSkills: [String], collegePersistence: CollegePersistence) -> [CareerCourseSkillGap] {
        guard !missingSkills.isEmpty else { return [] }
        var courses: [PlannerCourse] = []
        let semesters = (try? collegePersistence.profileRepository.fetchSemesters(limit: 50)) ?? []
        for semester in semesters {
            if let semesterCourses = try? collegePersistence.profileRepository.fetchCourses(forSemesterID: semester.id, limit: 80) {
                courses.append(contentsOf: semesterCourses)
            }
        }
        let catalogCourses = courses.map { course -> (code: String, title: String, text: String) in
            let code = course.code.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = course.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = [code, title].joined(separator: " ").lowercased()
            return (code, title, text)
        }.filter { !$0.code.isEmpty }

        return missingSkills.prefix(8).compactMap { skill in
            let needle = skill.lowercased()
            if let match = catalogCourses.first(where: { $0.text.contains(needle) }) {
                return CareerCourseSkillGap(
                    skill: skill,
                    courseCode: match.code,
                    courseTitle: match.title,
                    timing: .upcoming
                )
            }
            return CareerCourseSkillGap(skill: skill)
        }
    }
}
