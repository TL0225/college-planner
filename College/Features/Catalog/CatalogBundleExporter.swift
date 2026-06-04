// CatalogBundleExporter.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogBundleExporter.
// Data: CollegePersistence / repositories when applicable.

import Foundation

extension CollegePersistence {
    /// Builds, signs, and saves a read-only canonical catalog bundle; returns a temp URL suitable for ShareLink.
    func exportCatalogBundle(for universityName: String) throws -> URL {
        let bundle = try buildCatalogBundle(for: universityName)
        let envelope = try CatalogBundleSecurity.sign(bundle: bundle)
        try CatalogFileStore.save(envelope: envelope, for: universityName)
        return try CatalogFileStore.shareableCopy(for: universityName)
    }

    func buildCatalogBundle(for universityName: String) throws -> CatalogBundle {
        guard let repo = catalogRepository,
              let university = try repo.fetchUniversity(named: universityName) else {
            throw NSError(
                domain: "CatalogBundle",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "University not found: \(universityName)"]
            )
        }

        let departments = (try repo.fetchDepartments(universityID: university.id)).map { dept in
            BundledDepartment(
                id: dept.id,
                name: dept.name,
                code: dept.code,
                school: dept.school
            )
        }

        let majors = try repo.fetchAllMajors(universityID: university.id)
        let programs = majors.map { major in
            let deptNames = (major.departments ?? []).map(\.name).sorted()
            return BundledProgram(
                id: major.id,
                name: major.name,
                degreeLevel: major.degreeLevel,
                degreeType: major.degreeType,
                isMinor: major.isMinor,
                programURL: major.programURL,
                programURLs: major.programURLs,
                sourceCatoids: major.sourceCatoids,
                resolvedDepartment: major.resolvedDepartment,
                resolvedCollege: major.resolvedCollege,
                mappingConfidence: nil,
                mappingSource: nil,
                departmentNames: deptNames
            )
        }

        let requirementSections = (try repo.fetchDegreeRequirements(universityID: university.id)).map { req in
            BundledRequirementSection(
                id: req.id,
                programName: req.programName,
                programPoid: nil,
                totalCreditsRequired: nil,
                requirementGroupsJSON: nil,
                degreeType: req.degreeType,
                major: req.major,
                programURL: nil,
                requirementCategory: req.requirementCategory,
                sectionOrder: Int(req.sectionOrder),
                requiredCourses: nil,
                requiredCoursesDetailedJSON: nil,
                selectFromJSON: nil,
                selectFromDetailedJSON: nil,
                selectCount: nil,
                creditsRequired: Int(req.creditsRequired),
                descriptionText: req.descriptionText,
                requirementsHash: nil,
                lastScrapedAt: req.lastUpdated
            )
        }

        let scrapeStates = (try? repo.fetchScrapeStates(universityID: university.id))?.map { state in
            BundledScrapeState(
                catoid: state.catoid,
                catalogTitle: state.catalogTitle,
                courseCount: Int(state.courseCount),
                lastScrapedAt: state.lastScrapedAt
            )
        }

        let courses: [CatalogCourse] = try repo.fetchAllCatalogCourses(universityID: university.id).compactMap { course in
            var prereqRule: PrerequisiteRule?
            if let prereqJSON = course.prerequisiteRulesJSON,
               let jsonData = prereqJSON.data(using: .utf8) {
                prereqRule = try? JSONDecoder().decode(PrerequisiteRule.self, from: jsonData)
            }
            let corequisites = course.corequisiteCodes
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return CatalogCourse(
                id: course.id,
                courseCode: course.courseCode,
                title: course.title,
                description: course.descriptionText,
                credits: Int(course.credits),
                department: course.department,
                prerequisites: prereqRule,
                prerequisiteText: nil,
                corequisites: corequisites.isEmpty ? nil : corequisites,
                typicallyOffered: nil,
                catalogCoid: course.catalogCoid,
                previewDetailURL: nil
            )
        }

        return CatalogBundle(
            bundleVersion: CatalogBundle.currentVersion,
            exportedAt: Date(),
            schoolName: universityName,
            catalogURL: university.catalogURL,
            catalogFormat: university.catalogFormat,
            departments: departments,
            courses: courses,
            programs: programs,
            requirementSections: requirementSections,
            scrapeStates: scrapeStates ?? []
        )
    }
}
