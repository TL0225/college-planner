// CatalogRepository.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CatalogRepository.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// Bounded local store fetch helpers for per-school catalog stores (Phase 7b).
@MainActor
struct CatalogRepository {
    let context: ModelContext

    func fetchActiveUniversity() throws -> University? {
        var descriptor = FetchDescriptor<University>(
            predicate: #Predicate { $0.isActive == true }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchUniversity(id: UUID) throws -> University? {
        var descriptor = FetchDescriptor<University>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchUniversity(named name: String) throws -> University? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var descriptor = FetchDescriptor<University>(
            predicate: #Predicate { $0.name == trimmed }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchUniversities(limit: Int = 500) throws -> [University] {
        var descriptor = FetchDescriptor<University>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    @discardableResult
    func ensureUniversity(
        id: UUID,
        name: String,
        isActive: Bool = false
    ) throws -> University {
        if let existing = try fetchUniversity(id: id) {
            if existing.name != name {
                existing.name = name
            }
            if isActive {
                existing.isActive = true
            }
            return existing
        }
        let university = University(id: id, name: name, isActive: isActive)
        context.insert(university)
        return university
    }

    func upsertCourseScrapeState(
        universityID: UUID,
        catoid: String,
        catalogTitle: String?,
        courseCount: Int,
        scrapedAt: Date = .now
    ) throws {
        let trimmedCatoid = catoid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCatoid.isEmpty else { return }

        var descriptor = FetchDescriptor<CatalogScrapeState>(
            predicate: #Predicate { state in
                state.university?.id == universityID && state.catoid == trimmedCatoid
            }
        )
        descriptor.fetchLimit = 1

        let state: CatalogScrapeState
        if let existing = try context.fetch(descriptor).first {
            state = existing
        } else {
            let created = CatalogScrapeState(catoid: trimmedCatoid)
            created.university = try fetchUniversity(id: universityID)
            context.insert(created)
            state = created
        }

        if let catalogTitle, !catalogTitle.isEmpty {
            state.catalogTitle = catalogTitle
        }
        state.courseCount = Int32(max(0, courseCount))
        state.lastScrapedAt = scrapedAt
        ModelMergeCoalescer.scheduleSave(context)
    }

    struct CourseUpsertInput: Sendable {
        let courseCode: String
        let title: String
        let credits: Int16
        let descriptionText: String?
        let department: String?
        let isArchived: Bool
        let catalogStableID: UUID?
        let provenanceJSON: String?
        let prerequisiteRulesJSON: String?
    }

    func upsertCourses(universityID: UUID, inputs: [CourseUpsertInput]) throws {
        guard !inputs.isEmpty else { return }
        guard try fetchUniversity(id: universityID) != nil else { return }

        for input in inputs {
            let code = input.courseCode.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty else { continue }

            var descriptor = FetchDescriptor<CourseCatalog>(
                predicate: #Predicate { course in
                    course.university?.id == universityID && course.courseCode == code
                }
            )
            descriptor.fetchLimit = 1

            let course: CourseCatalog
            if let existing = try context.fetch(descriptor).first {
                course = existing
            } else {
                course = CourseCatalog(courseCode: code, title: input.title, credits: input.credits)
                course.university = try fetchUniversity(id: universityID)
                context.insert(course)
            }

            course.title = input.title.isEmpty ? code : input.title
            course.credits = input.credits
            course.descriptionText = input.descriptionText
            course.department = input.department
            course.isArchived = input.isArchived
            course.lastUpdated = .now
            if let stableID = input.catalogStableID {
                course.catalogStableID = stableID
            }
            if let provenanceJSON = input.provenanceJSON {
                course.provenanceJSON = provenanceJSON
            }
            if let prerequisiteRulesJSON = input.prerequisiteRulesJSON {
                course.prerequisiteRulesJSON = prerequisiteRulesJSON
            }
        }

        ModelMergeCoalescer.scheduleSave(context)
    }

    func loadStoredEntityIdentities(
        universityID: UUID,
        catalogVersionID: String
    ) throws -> [CatalogEntityIdentity] {
        var identities: [CatalogEntityIdentity] = []

        var majorDescriptor = FetchDescriptor<Major>(
            predicate: #Predicate { $0.university?.id == universityID }
        )
        majorDescriptor.fetchLimit = 20_000
        for major in try context.fetch(majorDescriptor) {
            guard let stableID = major.catalogStableID else { continue }
            let url = major.programURL ?? ""
            let programType = major.isMinor ? "minor" : (major.degreeType ?? major.degreeLevel)
            identities.append(
                CatalogEntityIdentity(
                    stableID: stableID,
                    entityType: .program,
                    catalogVersionID: catalogVersionID,
                    displayKey: CatalogEntityIdentityMatcher.displayKeyForProgram(
                        url: url,
                        name: major.name,
                        type: programType
                    )
                )
            )
        }

        var courseDescriptor = FetchDescriptor<CourseCatalog>(
            predicate: #Predicate { $0.university?.id == universityID }
        )
        courseDescriptor.fetchLimit = 50_000
        for course in try context.fetch(courseDescriptor) {
            guard let stableID = course.catalogStableID else { continue }
            identities.append(
                CatalogEntityIdentity(
                    stableID: stableID,
                    entityType: .course,
                    catalogVersionID: catalogVersionID,
                    displayKey: CatalogEntityIdentityMatcher.displayKeyForCourse(courseCode: course.courseCode)
                )
            )
        }

        return identities
    }

    /// Search catalog courses with a hard `fetchLimit`. When `performBackfill` is true, callers may
    /// run requirement-driven enrichment elsewhere; this repository only performs bounded fetches.
    func searchCatalogCourses(
        universityID: UUID,
        query: String,
        limit: Int = 50,
        performBackfill: Bool = false
    ) throws -> [CourseCatalog] {
        let effectiveLimit = min(max(limit, 1), 250)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        var descriptor = FetchDescriptor<CourseCatalog>(
            predicate: catalogCoursesPredicate(universityID: universityID, query: trimmed),
            sortBy: [SortDescriptor(\.courseCode, order: .forward)]
        )
        descriptor.fetchLimit = effectiveLimit

        let fetched = try context.fetch(descriptor)
        if performBackfill {
            // Phase 7f: mirror `CollegePersistence.backfillCatalogCoursesFromRequirementsIfNeeded`.
        }
        return fetched
    }

    func fetchCatalogCourse(id: UUID) throws -> CourseCatalog? {
        var descriptor = FetchDescriptor<CourseCatalog>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchMajors(universityID: UUID, limit: Int = 120) throws -> [Major] {
        var descriptor = FetchDescriptor<Major>(
            predicate: #Predicate { major in
                major.university?.id == universityID
            },
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        descriptor.fetchLimit = max(1, limit)
        return try context.fetch(descriptor)
    }

    func fetchCatalogCoursesPage(
        universityID: UUID,
        offset: Int,
        limit: Int,
        includeArchived: Bool = false
    ) throws -> [CourseCatalog] {
        let pageLimit = max(1, limit)
        var descriptor = FetchDescriptor<CourseCatalog>(
            predicate: catalogCoursesPredicate(
                universityID: universityID,
                query: "",
                includeArchived: includeArchived
            ),
            sortBy: [SortDescriptor(\.courseCode, order: .forward)]
        )
        descriptor.fetchLimit = pageLimit
        descriptor.fetchOffset = max(0, offset)
        return try context.fetch(descriptor)
    }

    // MARK: - Predicates

    private func catalogCoursesPredicate(
        universityID: UUID,
        query: String,
        includeArchived: Bool = false
    ) -> Predicate<CourseCatalog> {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if includeArchived {
                return #Predicate { course in
                    course.university?.id == universityID
                }
            }
            return #Predicate { course in
                course.university?.id == universityID && course.isArchived == false
            }
        }

        if includeArchived {
            return #Predicate { course in
                course.university?.id == universityID
                    && (course.courseCode.localizedStandardContains(trimmed)
                        || course.title.localizedStandardContains(trimmed))
            }
        }
        return #Predicate { course in
            course.university?.id == universityID
                && course.isArchived == false
                && (course.courseCode.localizedStandardContains(trimmed)
                    || course.title.localizedStandardContains(trimmed))
        }
    }
}