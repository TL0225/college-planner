// CollegeUnifiedCatalogStoreMigration.swift
// Feature: Core/Data
// Purpose: One-time import of per-school catalog SQLite stores into the unified app store.

import Foundation
import SwiftData

@MainActor
enum CollegeUnifiedCatalogStoreMigration {
    private static let completedKey = "storage.unifiedCatalogImport.v1"

    /// Imports a legacy catalog-only SQLite file into the unified store.
    @discardableResult
    static func importCatalogSQLite(at url: URL, into target: ModelContext) -> UUID? {
        guard let sourceContainer = try? ModelContainer(
            for: CollegeModelContainerFactory.catalogSchema,
            configurations: ModelConfiguration(url: url)
        ),
              let sourceUniversity = try? sourceContainer.mainContext.fetch(FetchDescriptor<University>()).first,
              copyCatalogUniversity(sourceUniversity, from: sourceContainer.mainContext, into: target, skipIfExists: true)
        else {
            return nil
        }
        return sourceUniversity.id
    }

    /// Writes a catalog-only SQLite extract for one university (signed export).
    static func materializeCatalogExtract(
        universityID: UUID,
        from source: ModelContext,
        to destinationURL: URL
    ) throws {
        let fm = FileManager.default
        ModelStoreMaintenance.removeSQLiteBundle(at: destinationURL)
        try fm.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var universityDescriptor = FetchDescriptor<University>(
            predicate: #Predicate { $0.id == universityID }
        )
        universityDescriptor.fetchLimit = 1
        guard let sourceUniversity = try source.fetch(universityDescriptor).first else {
            throw NSError(
                domain: "UnifiedStore",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "University not found in unified store."]
            )
        }

        let container = try ModelContainer(
            for: CollegeModelContainerFactory.catalogSchema,
            configurations: ModelConfiguration(url: destinationURL)
        )
        let target = container.mainContext
        guard copyCatalogUniversity(sourceUniversity, from: source, into: target, skipIfExists: false) else {
            throw NSError(
                domain: "UnifiedStore",
                code: 500,
                userInfo: [NSLocalizedDescriptionKey: "Failed to materialize catalog extract."]
            )
        }
        try target.save()
    }

    static func migrateIfNeeded(appDataStore: AppDataStore) {
        guard !UserDefaults.standard.bool(forKey: completedKey) else { return }

        let target = appDataStore.profileContext
        var importedAny = false
        var hadFailures = false

        for schoolID in legacySchoolIDs() {
            let url = CollegeModelContainerFactory.legacyCatalogStoreURL(for: schoolID)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            if importLegacyCatalogStore(at: url, into: target) {
                importedAny = true
            } else {
                hadFailures = true
                DiagnosticsEvent.emit(
                    subsystem: .catalog,
                    severity: .warning,
                    code: "LEGACY_CATALOG_IMPORT_FAILED",
                    message: "Failed to import legacy catalog store for school \(schoolID)."
                )
            }
        }

        if importedAny {
            try? target.save()
            appDataStore.bumpCatalogDataRevision()
        }

        if !hadFailures {
            UserDefaults.standard.set(true, forKey: completedKey)
        }
        if importedAny {
            quarantineLegacyCatalogStores()
        }
    }

    // MARK: - Discovery

    private static func legacySchoolIDs() -> [String] {
        var ids = Set(CatalogStoreCoordinator.shared.loadRegistry().map(\.schoolID))
        let root = CollegeModelContainerFactory.legacyCatalogStoresRootURL()
        if let dirs = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for dir in dirs where (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                ids.insert(dir.lastPathComponent)
            }
        }
        return ids.sorted()
    }

    // MARK: - Import

    @discardableResult
    private static func importLegacyCatalogStore(at url: URL, into target: ModelContext) -> Bool {
        guard let sourceContainer = try? ModelContainer(
            for: CollegeModelContainerFactory.catalogSchema,
            configurations: ModelConfiguration(url: url)
        ),
              let sourceUniversity = try? sourceContainer.mainContext.fetch(FetchDescriptor<University>()).first
        else {
            return false
        }
        return copyCatalogUniversity(
            sourceUniversity,
            from: sourceContainer.mainContext,
            into: target,
            skipIfExists: true
        )
    }

    @discardableResult
    private static func copyCatalogUniversity(
        _ sourceUniversity: University,
        from source: ModelContext,
        into target: ModelContext,
        skipIfExists: Bool
    ) -> Bool {
        let universityID = sourceUniversity.id
        if skipIfExists {
            var existingDescriptor = FetchDescriptor<University>(
                predicate: #Predicate { $0.id == universityID }
            )
            existingDescriptor.fetchLimit = 1
            if (try? target.fetch(existingDescriptor).first) != nil {
                return false
            }
        }

        let university = University(id: sourceUniversity.id, name: sourceUniversity.name, isActive: sourceUniversity.isActive)
        university.shortName = sourceUniversity.shortName
        university.catalogURL = sourceUniversity.catalogURL
        university.lastCatalogSync = sourceUniversity.lastCatalogSync
        university.catalogFormat = sourceUniversity.catalogFormat
        target.insert(university)

        var departmentByID: [UUID: Department] = [:]
        let sourceDepartments = ((try? source.fetch(FetchDescriptor<Department>())) ?? [])
            .filter { $0.university?.id == universityID }
        for sourceDepartment in sourceDepartments {
            let department = Department(
                id: sourceDepartment.id,
                name: sourceDepartment.name,
                lastUpdated: sourceDepartment.lastUpdated
            )
            department.code = sourceDepartment.code
            department.school = sourceDepartment.school
            department.university = university
            target.insert(department)
            departmentByID[department.id] = department
        }

        let sourceMajors = ((try? source.fetch(FetchDescriptor<Major>())) ?? [])
            .filter { $0.university?.id == universityID }

        var collegeByID: [UUID: CatalogCollege] = [:]
        let sourceColleges = ((try? source.fetch(FetchDescriptor<CatalogCollege>())) ?? [])
            .filter { $0.university?.id == universityID }
        for sourceCollege in sourceColleges {
            let college = CatalogCollege(
                id: sourceCollege.id,
                name: sourceCollege.name,
                lastUpdated: sourceCollege.lastUpdated
            )
            college.code = sourceCollege.code
            college.university = university
            target.insert(college)
            collegeByID[college.id] = college
        }

        let sourceEditions = ((try? source.fetch(FetchDescriptor<CatalogEdition>())) ?? [])
            .filter { $0.university?.id == universityID }
        for sourceEdition in sourceEditions {
            let edition = CatalogEdition(
                id: sourceEdition.id,
                editionKey: sourceEdition.editionKey,
                schoolID: sourceEdition.schoolID,
                label: sourceEdition.label,
                isPublished: sourceEdition.isPublished,
                createdAt: sourceEdition.createdAt
            )
            edition.sourceHash = sourceEdition.sourceHash
            edition.parserVersion = sourceEdition.parserVersion
            edition.replayConfigJSON = sourceEdition.replayConfigJSON
            edition.effectiveFrom = sourceEdition.effectiveFrom
            edition.effectiveTo = sourceEdition.effectiveTo
            edition.university = university
            target.insert(edition)
        }

        for sourceMajor in sourceMajors {
            let major = Major(
                id: sourceMajor.id,
                name: sourceMajor.name,
                degreeLevel: sourceMajor.degreeLevel,
                isMinor: sourceMajor.isMinor,
                lastUpdated: sourceMajor.lastUpdated
            )
            major.university = university
            major.degreeType = sourceMajor.degreeType
            major.programURL = sourceMajor.programURL
            major.programURLs = sourceMajor.programURLs
            major.sourceCatoids = sourceMajor.sourceCatoids
            major.resolvedDepartment = sourceMajor.resolvedDepartment
            major.resolvedCollege = sourceMajor.resolvedCollege
            major.catalogStableID = sourceMajor.catalogStableID
            major.provenanceJSON = sourceMajor.provenanceJSON
            major.mappingConfidence = sourceMajor.mappingConfidence
            major.mappingSource = sourceMajor.mappingSource
            major.departments = sourceMajor.departments?.compactMap { departmentByID[$0.id] }
            if let collegeID = sourceMajor.collegeEntity?.id {
                major.collegeEntity = collegeByID[collegeID]
            }
            target.insert(major)
        }

        let sourceCourses = ((try? source.fetch(FetchDescriptor<CourseCatalog>())) ?? [])
            .filter { $0.university?.id == universityID }
        for sourceCourse in sourceCourses {
            let course = CourseCatalog(
                id: sourceCourse.id,
                courseCode: sourceCourse.courseCode,
                title: sourceCourse.title,
                credits: sourceCourse.credits,
                isHydrated: sourceCourse.isHydrated,
                lastUpdated: sourceCourse.lastUpdated,
                isArchived: sourceCourse.isArchived
            )
            course.university = university
            course.catalogCoid = sourceCourse.catalogCoid
            course.descriptionText = sourceCourse.descriptionText
            course.prerequisiteText = sourceCourse.prerequisiteText
            course.prerequisiteRulesJSON = sourceCourse.prerequisiteRulesJSON
            course.department = sourceCourse.department
            course.catalogStableID = sourceCourse.catalogStableID
            course.provenanceJSON = sourceCourse.provenanceJSON
            if let departmentID = sourceCourse.departmentEntity?.id {
                course.departmentEntity = departmentByID[departmentID]
            }
            target.insert(course)
        }

        let sourceRequirements = ((try? source.fetch(FetchDescriptor<CatalogDegreeRequirement>())) ?? [])
            .filter { $0.university?.id == universityID }
        for sourceRequirement in sourceRequirements {
            let requirement = CatalogDegreeRequirement(
                id: sourceRequirement.id,
                degreeType: sourceRequirement.degreeType,
                major: sourceRequirement.major,
                requirementCategory: sourceRequirement.requirementCategory,
                sectionOrder: sourceRequirement.sectionOrder,
                creditsRequired: sourceRequirement.creditsRequired,
                lastUpdated: sourceRequirement.lastUpdated
            )
            requirement.university = university
            requirement.programName = sourceRequirement.programName
            requirement.programURL = sourceRequirement.programURL
            requirement.descriptionText = sourceRequirement.descriptionText
            requirement.lastScrapedAt = sourceRequirement.lastScrapedAt
            requirement.requiredCourses = sourceRequirement.requiredCourses
            requirement.requiredCoursesDetailedJSON = sourceRequirement.requiredCoursesDetailedJSON
            requirement.selectFromJSON = sourceRequirement.selectFromJSON
            requirement.selectFromDetailedJSON = sourceRequirement.selectFromDetailedJSON
            requirement.selectCount = sourceRequirement.selectCount
            requirement.requirementKind = sourceRequirement.requirementKind
            requirement.parentCategory = sourceRequirement.parentCategory
            requirement.displayTitle = sourceRequirement.displayTitle
            requirement.trackVariant = sourceRequirement.trackVariant
            requirement.requirementsHash = sourceRequirement.requirementsHash
            requirement.catalogStableID = sourceRequirement.catalogStableID
            requirement.provenanceJSON = sourceRequirement.provenanceJSON
            target.insert(requirement)
        }

        let sourcePolicies = ((try? source.fetch(FetchDescriptor<CatalogPolicyDocument>())) ?? [])
            .filter { $0.university?.id == universityID }
        for sourcePolicy in sourcePolicies {
            let policy = CatalogPolicyDocument(
                id: sourcePolicy.id,
                catoid: sourcePolicy.catoid,
                sourceURL: sourcePolicy.sourceURL,
                navTitle: sourcePolicy.navTitle,
                bodyText: sourcePolicy.bodyText,
                catalogScope: sourcePolicy.catalogScope,
                contentHash: sourcePolicy.contentHash,
                lastUpdated: sourcePolicy.lastUpdated
            )
            policy.university = university
            target.insert(policy)
        }

        let sourceStates = ((try? source.fetch(FetchDescriptor<CatalogScrapeState>())) ?? [])
            .filter { $0.university?.id == universityID }
        for sourceState in sourceStates {
            let state = CatalogScrapeState(
                id: sourceState.id,
                catoid: sourceState.catoid,
                courseCount: sourceState.courseCount,
                lastScrapedAt: sourceState.lastScrapedAt
            )
            state.university = university
            state.catalogTitle = sourceState.catalogTitle
            target.insert(state)
        }

        let sourceOverrides = ((try? source.fetch(FetchDescriptor<CourseOverride>())) ?? [])
            .filter { $0.university?.id == universityID }
        for sourceOverride in sourceOverrides {
            let override = CourseOverride(
                id: sourceOverride.id,
                courseCode: sourceOverride.courseCode,
                lastUpdated: sourceOverride.lastUpdated
            )
            override.university = university
            override.courseName = sourceOverride.courseName
            override.credits = sourceOverride.credits
            override.professor = sourceOverride.professor
            override.semesterText = sourceOverride.semesterText
            override.status = sourceOverride.status
            override.grade = sourceOverride.grade
            override.gradingType = sourceOverride.gradingType
            override.externalURL = sourceOverride.externalURL
            override.syllabusFileName = sourceOverride.syllabusFileName
            override.syllabusFileBookmarkData = sourceOverride.syllabusFileBookmarkData
            override.syllabusFileSizeBytes = sourceOverride.syllabusFileSizeBytes
            override.syllabusUploadedAt = sourceOverride.syllabusUploadedAt
            target.insert(override)
        }

        let universityName = sourceUniversity.name
        let sourceFulfillments = ((try? source.fetch(FetchDescriptor<RequirementFulfillment>())) ?? [])
            .filter { $0.university == universityName }
        for sourceFulfillment in sourceFulfillments {
            let fulfillment = RequirementFulfillment(
                id: sourceFulfillment.id,
                university: sourceFulfillment.university,
                programURL: sourceFulfillment.programURL,
                requirementCategory: sourceFulfillment.requirementCategory,
                courseCode: sourceFulfillment.courseCode,
                assignmentSource: sourceFulfillment.assignmentSource,
                createdAt: sourceFulfillment.createdAt
            )
            target.insert(fulfillment)
        }

        // GraduationPlanTerm is profile-partition data; omit from catalog-only legacy imports.

        return true
    }

    // MARK: - Cleanup

    private static func quarantineLegacyCatalogStores() {
        let fm = FileManager.default
        let root = CollegeModelContainerFactory.legacyCatalogStoresRootURL()
        let quarantine = root.deletingLastPathComponent()
            .appendingPathComponent("College/catalog-stores-migrated", isDirectory: true)
        guard fm.fileExists(atPath: root.path) else { return }
        if fm.fileExists(atPath: quarantine.path) {
            try? fm.removeItem(at: quarantine)
        }
        try? fm.moveItem(at: root, to: quarantine)
    }
}
