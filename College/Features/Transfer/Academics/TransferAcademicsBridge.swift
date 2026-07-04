// TransferAcademicsBridge.swift
// Feature: Transfer / Academics
// Purpose: Transfer Database — resolves target school, plan courses, and requirement targets.
// Data: Reads CollegePersistence (active university, planner, catalog requirements).

import Foundation

/// A planner course projected for transfer impact analysis.
struct TransferPlanCourse: Hashable, Sendable {
    var code: String
    var normalizedCode: String
    var title: String
    var credits: Int
    var grade: String?
    var bucket: TransferCourseScheduleBucket
}

/// A degree requirement reduced to its target course codes.
struct TransferRequirementTarget: Hashable, Sendable {
    var category: String
    var displayTitle: String
    var courseCodes: [String]
    var creditsRequired: Int
}

/// Identity of the institution a learner is transferring into.
struct TransferTargetSchool: Hashable, Sendable {
    var id: String
    var name: String
}

/// Bridges the Transfer Database to Academics/Catalog state without leaking persistence types.
@MainActor
struct TransferAcademicsBridge {
    let persistence: CollegePersistence
    let schoolsProvider: () -> [SchoolManifest]

    init(
        persistence: CollegePersistence,
        schoolsProvider: (() -> [SchoolManifest])? = nil
    ) {
        self.persistence = persistence
        self.schoolsProvider = schoolsProvider ?? { GitHubDataService().loadResolvedSchoolsList() }
    }

    /// The target school resolved from the active university (the school being transferred into).
    func resolveTargetSchool() -> TransferTargetSchool? {
        guard let name = persistence.getActiveUniversityName()?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !name.isEmpty else { return nil }
        let manifest = matchManifest(named: name)
        let id = manifest?.id ?? TransferNormalization.normalizeSchoolID(name)
        return TransferTargetSchool(id: id, name: manifest?.name ?? name)
    }

    /// Official source availability for the active target institution.
    func targetAvailability() -> TransferSourceAvailability {
        guard let name = persistence.getActiveUniversityName() else { return .none }
        return TransferSourceAvailability.from(manifest: matchManifest(named: name))
    }

    /// The manifest entry for an arbitrary school name (used to pick source institutions too).
    func matchManifest(named name: String) -> SchoolManifest? {
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return nil }
        let schools = schoolsProvider()
        if let exact = schools.first(where: {
            $0.name.compare(target, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            return exact
        }
        return schools.first(where: {
            $0.name.localizedCaseInsensitiveContains(target) || target.localizedCaseInsensitiveContains($0.name)
        })
    }

    /// Planner courses bucketed by schedule state (completed / in-progress / planned).
    func planCourses() -> [TransferPlanCourse] {
        var courses: [TransferPlanCourse] = []
        for semester in persistence.semesters {
            let plannedSemester = semester.isPlanned
            for course in semester.courses ?? [] where !course.isArchived {
                let code = course.code.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !code.isEmpty else { continue }
                let bucket: TransferCourseScheduleBucket
                if course.isCompleted {
                    bucket = .completed
                } else if plannedSemester {
                    bucket = .planned
                } else {
                    bucket = .inProgress
                }
                courses.append(
                    TransferPlanCourse(
                        code: code,
                        normalizedCode: CatalogImportTransforms.normalizeCourseCode(code),
                        title: course.name,
                        credits: Int(course.credits),
                        grade: course.grade,
                        bucket: bucket
                    )
                )
            }
        }
        return courses
    }

    /// Target degree-requirement course codes for the active university + primary major.
    func requirementTargets() -> [TransferRequirementTarget] {
        guard let university = persistence.getActiveUniversity(),
              let repo = persistence.catalogRepository else { return [] }
        let major = persistence.resolvedMajorNames().first ?? ""
        guard !major.isEmpty else { return [] }
        let degreeLevel = persistence.primaryDegreeLevel(default: "Undergraduate")

        let rows = (try? repo.fetchDegreeRequirementsForMajor(
            universityID: university.id,
            majorDisplay: major,
            degreeType: nil,
            degreeLevel: degreeLevel
        )) ?? []

        return rows.compactMap { row in
            let codes = requirementCourseCodes(row)
            guard !codes.isEmpty else { return nil }
            return TransferRequirementTarget(
                category: row.requirementCategory,
                displayTitle: (row.displayTitle?.isEmpty == false ? row.displayTitle : nil) ?? row.requirementCategory,
                courseCodes: codes,
                creditsRequired: Int(row.creditsRequired)
            )
        }
    }

    private func requirementCourseCodes(_ row: CatalogDegreeRequirement) -> [String] {
        var codes = Set<String>()
        if let raw = row.requiredCourses, !raw.isEmpty {
            for token in raw.split(separator: ",") {
                let normalized = CatalogImportTransforms.normalizeCourseCode(String(token))
                if !normalized.isEmpty { codes.insert(normalized) }
            }
        }
        if let detailedJSON = row.requiredCoursesDetailedJSON,
           let detailed = AcademicProgramHelpers.decodeDetailedCourseList(detailedJSON) {
            for course in detailed {
                let normalized = CatalogImportTransforms.normalizeCourseCode(course.code)
                if !normalized.isEmpty { codes.insert(normalized) }
            }
        }
        for token in AcademicProgramHelpers.decodeJSONCourseList(row.selectFromJSON) {
            let normalized = CatalogImportTransforms.normalizeCourseCode(token)
            if !normalized.isEmpty { codes.insert(normalized) }
        }
        if let selectDetailedJSON = row.selectFromDetailedJSON,
           let selectDetailed = AcademicProgramHelpers.decodeDetailedCourseList(selectDetailedJSON) {
            for course in selectDetailed {
                let normalized = CatalogImportTransforms.normalizeCourseCode(course.code)
                if !normalized.isEmpty { codes.insert(normalized) }
            }
        }
        return codes.sorted()
    }
}
