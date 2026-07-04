// AssistantLearningProfileBuilder.swift
// Feature: Assistant
// Purpose: Tier 1 learning profile from planner courses (Ship A).

import Foundation

struct AssistantLearningProfileCourse: Codable, Sendable, Equatable {
    let code: String
    let title: String
    let status: String
    let semesterLabel: String
    let majorRelevant: Bool
}

struct AssistantLearningProfileCoverage: Codable, Sendable, Equatable {
    let tier1CourseCount: Int
    let majorRelevantCount: Int
    let tier2Available: Bool
    let tier3Available: Bool
    var personalizationEligible: Bool { majorRelevantCount >= 2 }
}

struct AssistantLearningProfile: Codable, Sendable, Equatable {
    let courses: [AssistantLearningProfileCourse]
    let coverage: AssistantLearningProfileCoverage
    let compressedSummary: String
}

enum AssistantLearningProfileBuilder {
    static let tier1CharCap = 1_200
    static let maxCourses = 12

    @MainActor
    static func tier2CatalogBlock(
        persistence: CollegePersistence,
        courseCodes: [String],
        maxCourses: Int = 10,
        charsPerCourse: Int = 200
    ) -> (text: String, available: Bool) {
        var lines: [String] = []
        for code in courseCodes.prefix(maxCourses) {
            guard let course = persistence.getCatalogCourse(code: code) else { continue }
            let desc = (course.descriptionText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !desc.isEmpty else { continue }
            lines.append("- \(code): \(String(desc.prefix(charsPerCourse)))")
        }
        guard !lines.isEmpty else { return ("", false) }
        return (lines.joined(separator: "\n"), true)
    }

    @MainActor
    static func build(
        persistence: CollegePersistence,
        majorNames: [String],
        programURL: String?
    ) -> AssistantLearningProfile {
        let rows = fetchPlannerCourses(persistence: persistence)
        let primaryMajor = majorNames.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let requirementCodes = requirementCodesForMajor(persistence: persistence, majorName: primaryMajor, programURL: programURL)

        var courses: [AssistantLearningProfileCourse] = []
        courses.reserveCapacity(min(maxCourses, rows.count))
        for row in rows.prefix(maxCourses) {
            let relevant = isMajorRelevantCourse(
                code: row.code,
                title: row.title,
                majorName: primaryMajor,
                requirementCodes: requirementCodes
            )
            courses.append(
                AssistantLearningProfileCourse(
                    code: row.code,
                    title: row.title,
                    status: row.status,
                    semesterLabel: row.semesterLabel,
                    majorRelevant: relevant
                )
            )
        }

        let majorRelevantCount = courses.filter(\.majorRelevant).count
        let tier2 = tier2CatalogBlock(
            persistence: persistence,
            courseCodes: courses.map(\.code)
        )
        let tier3 = tier3SyllabusBlock(
            persistence: persistence,
            courseCodes: courses.map(\.code)
        )
        let coverage = AssistantLearningProfileCoverage(
            tier1CourseCount: courses.count,
            majorRelevantCount: majorRelevantCount,
            tier2Available: tier2.available,
            tier3Available: tier3.available
        )
        var summary = compress(courses: courses, coverage: coverage)
        if tier2.available {
            summary += "\n\nCatalog descriptions:\n\(tier2.text)"
        }
        if tier3.available {
            summary += "\n\nSyllabus notes:\n\(tier3.text)"
        }
        return AssistantLearningProfile(courses: courses, coverage: coverage, compressedSummary: summary)
    }

    @MainActor
    static func tier3SyllabusBlock(
        persistence: CollegePersistence,
        courseCodes: [String],
        maxEntries: Int = 6,
        charsPerEntry: Int = 150
    ) -> (text: String, available: Bool) {
        let codeSet = Set(courseCodes.map { $0.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        guard !codeSet.isEmpty else { return ("", false) }
        let syllabiCategory = "Syllabi"
        let docs = persistence.vaultDocuments.filter { doc in
            guard !doc.isFolder else { return false }
            guard doc.category.trimmingCharacters(in: .whitespacesAndNewlines) == syllabiCategory else { return false }
            if let linked = doc.courseCodeLinked?.uppercased().trimmingCharacters(in: .whitespacesAndNewlines),
               codeSet.contains(linked) {
                return true
            }
            let label = (doc.customDisplayName ?? doc.fileName).uppercased()
            return codeSet.contains(where: { label.contains($0) })
        }
        var lines: [String] = []
        for doc in docs.prefix(maxEntries) {
            let code = doc.courseCodeLinked?.trimmingCharacters(in: .whitespacesAndNewlines) ?? doc.fileName
            let note = (doc.summaryText ?? doc.userNotes ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !note.isEmpty else { continue }
            lines.append("- \(code): \(String(note.prefix(charsPerEntry)))")
        }
        guard !lines.isEmpty else { return ("", false) }
        return (lines.joined(separator: "\n"), true)
    }

    static func isMajorRelevantCourse(
        code: String,
        title: String,
        majorName: String,
        requirementCodes: Set<String>
    ) -> Bool {
        let normalizedCode = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedCode.isEmpty else { return false }
        if requirementCodes.contains(normalizedCode) { return true }

        let major = majorName.lowercased()
        let titleLower = title.lowercased()
        if !major.isEmpty {
            let majorTokens = major.split(separator: " ").map(String.init)
            if majorTokens.contains(where: { titleLower.contains($0) && $0.count > 3 }) {
                return true
            }
            if let dept = departmentPrefix(from: normalizedCode), major.contains(dept.lowercased()) {
                return true
            }
        }

        let interdisciplinary = ["data", "ethics", "human computer", "hci", "technical writing", "statistics", "security", "machine learning"]
        if interdisciplinary.contains(where: { titleLower.contains($0) }) {
            return true
        }
        return false
    }

    private static func departmentPrefix(from code: String) -> String? {
        let parts = code.split(separator: " ", omittingEmptySubsequences: true)
        guard let first = parts.first else { return nil }
        let letters = first.filter { $0.isLetter }
        guard letters.count >= 2 else { return nil }
        return String(letters)
    }

    private struct PlannerRow {
        let code: String
        let title: String
        let status: String
        let semesterLabel: String
    }

    @MainActor
    private static func fetchPlannerCourses(persistence: CollegePersistence) -> [PlannerRow] {
        var out: [PlannerRow] = []
        let semesters = persistence.semesters
        for semester in semesters {
            let label = "\(semester.season) \(semester.year)"
            let courses = (try? persistence.profileRepository.fetchCourses(forSemesterID: semester.id, limit: 40)) ?? []
            for course in courses {
                let code = course.code.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !code.isEmpty else { continue }
                let title = course.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let status = course.status.trimmingCharacters(in: .whitespacesAndNewlines)
                out.append(PlannerRow(code: code, title: title.isEmpty ? code : title, status: status.isEmpty ? "planned" : status, semesterLabel: label))
            }
        }
        return out
    }

    @MainActor
    private static func requirementCodesForMajor(
        persistence: CollegePersistence,
        majorName: String,
        programURL: String?
    ) -> Set<String> {
        var requirements = persistence.getDegreeRequirementsForMajorDisplay(majorName)
        if requirements.isEmpty, let programURL {
            let degreeType = (persistence.primaryDegreeType() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            requirements = persistence.getDegreeRequirements(programURL: programURL, degreeType: degreeType)
        }
        var codes = Set<String>()
        for req in requirements {
            let legacy = (req.requiredCourses ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
                .filter { !$0.isEmpty }
            codes.formUnion(legacy)
            if let json = req.selectFromJSON {
                let parsed = persistence.decodeJSONCourseList(json)
                if !parsed.isEmpty {
                    codes.formUnion(parsed.map { $0.uppercased() })
                }
            }
        }
        return codes
    }

    private static func compress(courses: [AssistantLearningProfileCourse], coverage: AssistantLearningProfileCoverage) -> String {
        var lines: [String] = [
            "Learning profile (Tier 1): \(coverage.tier1CourseCount) courses, \(coverage.majorRelevantCount) major-relevant.",
            "personalizationEligible: \(coverage.personalizationEligible)"
        ]
        for c in courses {
            let rel = c.majorRelevant ? "relevant" : "other"
            lines.append("- \(c.code) \(c.title) [\(c.status), \(c.semesterLabel), \(rel)]")
        }
        var text = lines.joined(separator: "\n")
        if text.count > tier1CharCap {
            text = String(text.prefix(tier1CharCap)) + "\n...(truncated)"
        }
        return text
    }
}
