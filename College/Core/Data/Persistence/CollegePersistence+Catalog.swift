// CollegePersistence+Catalog.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CatalogCapability.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension CollegePersistence {
    typealias RequirementsRefreshResult = CatalogRepository.RequirementsRefreshResult

    struct CatalogCapability: Sendable, Equatable {
        var coursesReady: Bool
        var programsReady: Bool
        var requirementsReady: Bool
        var vectorsReady: Bool
        var fullArchiveReady: Bool

        var academicReady: Bool {
            coursesReady && programsReady && requirementsReady
        }

        static let empty = CatalogCapability(
            coursesReady: false,
            programsReady: false,
            requirementsReady: false,
            vectorsReady: false,
            fullArchiveReady: false
        )
    }

    struct ProgramPickerSection: Equatable, Sendable {
        let title: String
        let labels: [String]
    }

    func catalogCapabilities(universityName: String) async -> CatalogCapability {
        catalogCapabilitiesSync(universityName: universityName)
    }

    func catalogCapabilitiesSync(universityName: String) -> CatalogCapability {
        let trimmed = universityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }

        let programs = catalogProgramCount(for: trimmed)
        let courses = countCatalogCourses(universityName: trimmed)
        let requirements = countDegreeRequirements(universityName: trimmed)
        let vectors = catalogVectorsReady(universityName: trimmed)
        let archiveReady = catalogArchiveReady(universityName: trimmed)

        return CatalogCapability(
            coursesReady: courses > 0,
            programsReady: programs > 0,
            requirementsReady: requirements > 0,
            vectorsReady: vectors,
            fullArchiveReady: archiveReady
        )
    }

    func catalogProgramCount(for universityName: String) -> Int {
        let trimmed = universityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let repo = catalogRepository,
              let university = try? repo.fetchUniversity(named: trimmed) else {
            return 0
        }
        return (try? repo.fetchAllMajors(universityID: university.id).count) ?? 0
    }

    func fetchDepartmentGroups(
        for universityName: String,
        degreeLevel: String? = nil,
        sourceCatoid: String? = nil,
        includeCollegeBuckets: Bool = false
    ) -> [(group: String, departments: [String])] {
        _ = degreeLevel
        _ = sourceCatoid
        _ = includeCollegeBuckets
        let trimmed = universityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let repo = catalogRepository,
              let university = try? repo.fetchUniversity(named: trimmed) else {
            return []
        }
        let departments = (try? repo.fetchDepartments(universityID: university.id)) ?? []
        var grouped: [String: [String]] = [:]
        for department in departments {
            let bucket = (department.school ?? "Departments").trimmingCharacters(in: .whitespacesAndNewlines)
            let name = department.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            grouped[bucket, default: []].append(name)
        }
        return grouped
            .map { (group: $0.key, departments: $0.value.sorted()) }
            .sorted { $0.group.localizedCaseInsensitiveCompare($1.group) == .orderedAscending }
    }

    func catalogPresence(universityName: String) async -> (courses: Int, departments: Int, majors: Int, minors: Int) {
        let trimmed = universityName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let repo = catalogRepository,
              let university = try? repo.fetchUniversity(named: trimmed) else {
            return (0, 0, 0, 0)
        }
        let majors = (try? repo.fetchAllMajors(universityID: university.id)) ?? []
        let minors = majors.filter(\.isMinor).count
        let majorCount = majors.count - minors
        let departments = (try? repo.fetchDepartments(universityID: university.id).count) ?? 0
        let courses = (try? repo.fetchCatalogCourseCount(universityID: university.id)) ?? 0
        return (courses, departments, majorCount, minors)
    }

    func fetchProgramPickerSections(
        for universityName: String,
        degreeLevels: [String],
        sourceCatoid: String?,
        includeMinors: Bool,
        includeCollegeBuckets: Bool,
        allowLegacyCatoidFallback: Bool = true
    ) -> [ProgramPickerSection] {
        _ = includeCollegeBuckets
        var sectionsByTitle: [String: [String]] = [:]
        var sectionOrder: [String] = []

        func ingest(level: String, catoid: String?) {
            let labels = CatalogProgramReadBridge.fetchMajors(
                for: universityName,
                degreeLevel: level,
                includeMinors: includeMinors,
                sourceCatoid: catoid,
                appDataStore: appDataStore
            )
            guard !labels.isEmpty else { return }
            let title = "\(level) > \(universityName)"
            if sectionsByTitle[title] == nil {
                sectionOrder.append(title)
                sectionsByTitle[title] = []
            }
            for label in labels where sectionsByTitle[title]?.contains(label) == false {
                sectionsByTitle[title, default: []].append(label)
            }
        }

        for level in degreeLevels {
            let trimmedLevel = level.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLevel.isEmpty else { continue }
            ingest(level: trimmedLevel, catoid: sourceCatoid)
            if allowLegacyCatoidFallback,
               let catoid = sourceCatoid?.trimmingCharacters(in: .whitespacesAndNewlines),
               !catoid.isEmpty,
               sectionsByTitle.isEmpty {
                ingest(level: trimmedLevel, catoid: nil)
            }
        }

        return sectionOrder.compactMap { title in
            guard let labels = sectionsByTitle[title] else { return nil }
            let sorted = labels.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            guard !sorted.isEmpty else { return nil }
            return ProgramPickerSection(title: title, labels: sorted)
        }
    }

    func canonicalStoredProgramURL(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let withoutFragment = trimmed.split(separator: "#", maxSplits: 1).first.map(String.init) ?? trimmed
        if let first = withoutFragment.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).first,
           !first.isEmpty {
            return first
        }
        return withoutFragment
    }

    func programRequirementsStorageURL(from programURL: String, trackVariant: String?) -> String {
        let trimmed = programURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let track = (trackVariant ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = canonicalStoredProgramURL(trimmed)
        guard !track.isEmpty else { return base }
        if base.contains("#track=") { return base }
        return "\(base)#track=\(track)"
    }

    private func countCatalogCourses(universityName: String) -> Int {
        guard let repo = catalogRepository,
              let university = try? repo.fetchUniversity(named: universityName) else {
            return 0
        }
        return (try? repo.fetchCatalogCourseCount(universityID: university.id)) ?? 0
    }

    private func countDegreeRequirements(universityName: String) -> Int {
        guard let repo = catalogRepository,
              let university = try? repo.fetchUniversity(named: universityName) else {
            return 0
        }
        return (try? repo.fetchDegreeRequirementCount(universityID: university.id)) ?? 0
    }

    private func catalogVectorsReady(universityName: String) -> Bool {
        guard let schoolID = catalogManifestSchoolID(forUniversityName: universityName) else {
            return false
        }
        return CatalogIntegrityReport.load(schoolID: schoolID)?.vectorsReady ?? false
    }

    private func catalogArchiveReady(universityName: String) -> Bool {
        guard let schoolID = catalogManifestSchoolID(forUniversityName: universityName) else {
            return false
        }
        if CatalogIntegrityReport.load(schoolID: schoolID)?.archiveReady == true {
            return true
        }
        return CatalogArchiveStore.loadIndex(schoolID: schoolID) != nil
    }

    func catalogManifestSchoolID(forUniversityName name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return SchoolManifestCatalog.bundled().first(where: {
            $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        })?.id
    }

    static func isUnusableCatalogDescription(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        let lower = trimmed.lowercased()
        return lower == "n/a" || lower == "na" || lower == "none" || lower == "tbd"
    }

    func fetchCatalogProgramsForRequirementsPicker(universityNames: [String]) -> [Major] {
        let names = Set(
            universityNames
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        guard !names.isEmpty, let repo = catalogRepository else { return [] }

        var rows: [Major] = []
        for name in universityNames {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let university = try? repo.fetchUniversity(named: trimmed) else { continue }
            let majors = (try? repo.fetchAllMajors(universityID: university.id)) ?? []
            rows.append(contentsOf: majors)
        }

        return rows
            .filter { major in
                let uni = (major.university?.name ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                return names.contains(uni)
            }
            .sorted { lhs, rhs in
                let lUni = lhs.university?.name ?? ""
                let rUni = rhs.university?.name ?? ""
                if lUni != rUni {
                    return lUni.localizedCaseInsensitiveCompare(rUni) == .orderedAscending
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    func fetchCatalogUniversityNames() -> [String] {
        guard let repo = catalogRepository else { return [] }
        return (try? repo.fetchUniversities().map {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }) ?? []
    }

    func catalogProgramPickerLabel(for major: Major) -> String? {
        formattedMajorPickerLabel(name: major.name, degreeType: major.degreeType, isMinor: major.isMinor)
    }

    /// Picker/onboarding label, e.g. `Computer Science (BS)`.
    func formattedMajorPickerLabel(name: String?, degreeType: String?, isMinor: Bool) -> String? {
        guard let rawName = name?.trimmingCharacters(in: .whitespacesAndNewlines), !rawName.isEmpty else {
            return nil
        }
        if isMinor { return rawName }
        guard let degreeType = degreeType?.trimmingCharacters(in: .whitespacesAndNewlines), !degreeType.isEmpty else {
            return rawName
        }

        var trimmedName = rawName
            .replacingOccurrences(of: ",\\s*$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        trimmedName = trimmedName.replacingOccurrences(
            of: #"\s*\([^)]+\)\s*$"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedName.contains("/") { return trimmedName }
        if trimmedName.hasSuffix("(\(degreeType))") { return trimmedName }
        return "\(trimmedName) (\(degreeType))"
    }

    func catalogProgramPickerSectionTitle(for major: Major) -> String? {
        let level = major.degreeLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !level.isEmpty else { return nil }

        var bucket = catalogOwnershipLabel(major.resolvedCollege)
        if bucket.isEmpty { bucket = catalogOwnershipLabel(major.resolvedDepartment) }
        if bucket.isEmpty, let first = major.departments?.first {
            let school = catalogOwnershipLabel(first.school)
            let deptName = catalogOwnershipLabel(first.name)
            bucket = school.isEmpty ? deptName : school
        }
        if bucket.isEmpty { return level }
        return "\(level) > \(bucket)"
    }

    typealias CatalogScrapeDataPresence = CatalogRepository.CatalogScrapeDataPresence

    func existingCatalogCourseCount(for universityName: String) -> Int {
        guard let repo = catalogRepository,
              let university = try? repo.fetchUniversity(named: universityName) else {
            return 0
        }
        return (try? repo.fetchCatalogCourseCount(universityID: university.id)) ?? 0
    }

    func catalogScrapeDataPresence(
        forUniversityName universityName: String,
        programURLContains programURLNeedle: String?
    ) -> CatalogScrapeDataPresence {
        guard let repo = catalogRepository else { return .init() }
        return (try? repo.catalogScrapeDataPresence(
            forUniversityName: universityName,
            programURLContains: programURLNeedle
        )) ?? .init()
    }

    func resolveProgramURL(
        programDisplay: String,
        universityName: String,
        degreeLevel: String,
        degreeType: String?,
        isMinor: Bool,
        ownershipHint: String? = nil
    ) -> String? {
        guard let repo = catalogRepository else { return nil }
        return try? repo.resolveProgramURL(
            programDisplay: programDisplay,
            universityName: universityName,
            degreeLevel: degreeLevel,
            degreeType: degreeType,
            isMinor: isMinor,
            ownershipHint: ownershipHint
        )
    }

    // `refreshProgramRequirementsForCatalogPick` — see `CollegePersistence+ProgramRequirementsScrape.swift`

    private func catalogOwnershipLabel(_ raw: String?) -> String {
        var value = (raw ?? "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        if value.hasPrefix("Department of ") {
            value = String(value.dropFirst("Department of ".count))
        }
        return value
    }

    func fetchCatalogDegreeLevels(for universityName: String) -> [String] {
        guard let repo = catalogRepository,
              let university = try? repo.fetchUniversity(named: universityName) else {
            return []
        }
        let majors = (try? repo.fetchAllMajors(universityID: university.id)) ?? []
        let levels = Set(
            majors.compactMap { major in
                let level = major.degreeLevel.trimmingCharacters(in: .whitespacesAndNewlines)
                return level.isEmpty ? nil : level
            }
        )
        return levels.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func fetchDepartments(for universityName: String, degreeLevel: String) -> [String] {
        fetchDepartmentGroups(for: universityName, degreeLevel: degreeLevel, sourceCatoid: nil)
            .flatMap(\.departments)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func fetchDegreeTypes(for universityName: String, degreeLevel: String) -> [String] {
        guard let repo = catalogRepository,
              let university = try? repo.fetchUniversity(named: universityName) else {
            return []
        }
        let trimmedLevel = degreeLevel.trimmingCharacters(in: .whitespacesAndNewlines)
        let majors = (try? repo.fetchAllMajors(universityID: university.id)) ?? []
        let types = Set(
            majors.compactMap { major -> String? in
                let level = major.degreeLevel.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmedLevel.isEmpty || level.caseInsensitiveCompare(trimmedLevel) == .orderedSame else {
                    return nil
                }
                let type = (major.degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return type.isEmpty ? nil : type
            }
        )
        return types.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func resolvedDegreeTypeOptions(
        for universityName: String,
        degreeLevel: String,
        currentSelection: String
    ) -> [String] {
        var options = fetchDegreeTypes(for: universityName, degreeLevel: degreeLevel)
        let current = currentSelection.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty, !options.contains(current) {
            options.insert(current, at: 0)
        }
        if options.isEmpty {
            options = DegreeTokenRegistry.allFullPickerLabels()
        }
        return options
    }

    func resolvedCatalogDepartment(
        forMajorDisplay majorDisplay: String,
        universityName: String,
        degreeLevel: String,
        degreeType: String?
    ) -> String? {
        let cleaned = AcademicProgramHelpers.cleanedProgramNameFromDisplay(majorDisplay)
        guard let repo = catalogRepository,
              let university = try? repo.fetchUniversity(named: universityName) else {
            return nil
        }
        let majors = (try? repo.fetchAllMajors(universityID: university.id)) ?? []
        let match = majors.first { major in
            let nameMatch = major.name.caseInsensitiveCompare(cleaned) == .orderedSame
                || major.name.caseInsensitiveCompare(majorDisplay) == .orderedSame
            guard nameMatch, !major.isMinor else { return false }
            let level = major.degreeLevel.trimmingCharacters(in: .whitespacesAndNewlines)
            if !degreeLevel.isEmpty, level.caseInsensitiveCompare(degreeLevel) != .orderedSame { return false }
            if let degreeType, !degreeType.isEmpty {
                let type = (major.degreeType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if type.caseInsensitiveCompare(degreeType) != .orderedSame { return false }
            }
            return true
        }
        return match?.resolvedDepartment?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    func fetchCertificates(for universityName: String, sourceCatoid: String? = nil) -> [String] {
        _ = sourceCatoid
        guard let repo = catalogRepository,
              let university = try? repo.fetchUniversity(named: universityName) else {
            return []
        }
        let majors = (try? repo.fetchAllMajors(universityID: university.id)) ?? []
        return majors
            .filter { major in
                let type = (major.degreeType ?? "").lowercased()
                return type.contains("certificate") || type.contains("credential")
            }
            .map(\.name)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func replaceCatalogPolicyDocuments(
        forUniversityName universityName: String,
        catoid: String,
        rows: [(sourceURL: String, navTitle: String, sectionHeading: String, bodyText: String, catalogScope: String, contentHash: String, binding: String)]
    ) throws {
        _ = rows.map(\.binding)
        guard let repo = catalogRepository,
              let university = try? repo.fetchUniversity(named: universityName) else {
            return
        }
        let context = repo.context
        let trimmedCatoid = catoid.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = (try? context.fetch(FetchDescriptor<CatalogPolicyDocument>())) ?? []
        for doc in existing where doc.university?.id == university.id {
            if trimmedCatoid.isEmpty || doc.catoid == trimmedCatoid {
                context.delete(doc)
            }
        }
        for row in rows {
            let doc = CatalogPolicyDocument(
                catoid: trimmedCatoid,
                sourceURL: row.sourceURL,
                navTitle: row.navTitle.isEmpty ? row.sectionHeading : row.navTitle,
                bodyText: row.bodyText,
                catalogScope: row.catalogScope,
                contentHash: row.contentHash
            )
            doc.university = university
            context.insert(doc)
        }
        try context.save()
        bumpCatalogDataRevision()
    }
}

extension CollegePersistence {
    typealias CatalogScrapePurgeCounts = CatalogRepository.CatalogScrapePurgeCounts

    func resolveUniversity(byName name: String) -> University? {
        try? catalogRepository?.fetchUniversity(named: name)
    }

    func purgeCatalogScrapeData(
        forUniversityName universityName: String,
        programURLContains programURLNeedle: String? = nil
    ) -> CatalogScrapePurgeCounts {
        guard let repo = catalogRepository else { return .init() }
        return (try? repo.purgeCatalogScrapeData(
            forUniversityName: universityName,
            programURLContains: programURLNeedle
        )) ?? .init()
    }

    func catalogScrapeDataPresence(
        forUniversityNames universityNames: [String],
        programURLNeedles needles: [String?]
    ) -> CatalogScrapeDataPresence {
        var combined = CatalogScrapeDataPresence()
        guard let repo = catalogRepository else { return combined }
        for (index, name) in universityNames.enumerated() {
            let needle = index < needles.count ? needles[index] : nil
            let presence = (try? repo.catalogScrapeDataPresence(
                forUniversityName: name,
                programURLContains: needle
            )) ?? .init()
            combined.majors += presence.majors
            combined.degreeRequirements += presence.degreeRequirements
            combined.requirementFulfillments += presence.requirementFulfillments
            combined.catalogCourses += presence.catalogCourses
            combined.departments += presence.departments
            combined.scrapeStates += presence.scrapeStates
            combined.policyDocuments += presence.policyDocuments
        }
        return combined
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}