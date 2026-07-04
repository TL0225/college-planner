// CatalogBundleImporter.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogBundleImporter.
// Data: CollegePersistence / repositories when applicable.

import Foundation

extension CollegePersistence {
    @MainActor
    func importCatalogBundle(from url: URL) async throws -> CatalogBundleImportSummary {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        let (bundle, envelope, fingerprint) = try await CatalogBundleSecurity.verifyFileOffMain(at: url)

        switch CatalogBundleValidator.validate(bundle) {
        case .valid:
            break
        case .invalid(let reason):
            throw CatalogBundleSecurityError.validationFailed(reason)
        }

        let schoolName = bundle.schoolName

        try CatalogProgramWriteBridge.saveDepartments(
            bundle.departments.map { (name: $0.name, code: $0.code, school: $0.school) },
            for: schoolName
        )

        let majorsPayload = buildSaveMajorsPayload(from: bundle)
        try CatalogProgramWriteBridge.savePrograms(
            majorsPayload,
            for: schoolName
        )

        let profile = SchoolProfile(
            schoolID: schoolName.replacingOccurrences(of: " ", with: "_").lowercased(),
            schoolName: schoolName,
            catalogURL: bundle.catalogURL ?? "",
            version: "1.0.0-catalog-bundle-import",
            lastUpdated: bundle.exportedAt,
            courses: bundle.courses,
            degreeRequirements: [],
            policies: SchoolPolicies(
                transferCreditLimit: nil,
                minorTransferLimit: nil,
                maxCreditsPerSemester: nil,
                minCreditsForFullTime: nil,
                gradeForCredit: nil,
                repeatCoursePolicy: nil
            )
        )
        try await importSchoolCatalog(profile)
        _ = setActiveUniversity(named: schoolName)
        CatalogStoreSnapshotBridge.materializePerSchoolCatalogSnapshot(universityName: schoolName)

        for state in bundle.scrapeStates where !state.catoid.isEmpty {
            await CatalogScrapeStateBridge.upsertCourseScrapeState(
                universityName: schoolName,
                catoid: state.catoid,
                catalogTitle: state.catalogTitle,
                courseCount: state.courseCount,
                scrapedAt: state.lastScrapedAt
            )
        }

        try CatalogFileStore.save(envelope: envelope, for: schoolName)
        _ = CatalogIngestReconciler.reconcile(
            after: CatalogIngestSnapshot(
                schoolID: schoolName.replacingOccurrences(of: " ", with: "_").lowercased(),
                schoolName: schoolName,
                scope: .bundleImport,
                format: "bundle",
                importedAt: Date(),
                courseCount: bundle.courses.count,
                programCount: bundle.programs.count,
                requirementCount: bundle.requirementSections.count,
                policyCount: 0
            )
        )

        if let university = getActiveUniversity() {
            let universityID = university.id
            CatalogIngestPipeline.postCatalogDataDidCommit(
                universityID: universityID,
                reason: "catalog bundle import committed",
                commitPhase: .profile,
                programCount: bundle.programs.count,
                schoolID: schoolName.replacingOccurrences(of: " ", with: "_").lowercased()
            )
        }

        return CatalogBundleImportSummary(
            schoolName: schoolName,
            courseCount: bundle.courses.count,
            programCount: bundle.programs.count,
            requirementSectionCount: bundle.requirementSections.count,
            exportedAt: bundle.exportedAt,
            signerFingerprint: fingerprint,
            wasTrustedSource: CatalogBundleTrustStore.shared.isTrusted(fingerprint: fingerprint)
        )
    }

    private func buildSaveMajorsPayload(
        from bundle: CatalogBundle
    ) -> [(
        name: String,
        degreeLevel: String,
        degreeType: String?,
        isMinor: Bool,
        department: String?,
        url: String?,
        resolvedDepartment: String?,
        resolvedCollege: String?,
        mappingConfidence: Double?,
        mappingSource: String?,
        requirements: [DegreeRequirement]?,
        trackVariant: String?,
        parentProgramKey: String?
    )] {
        var requirementsByProgramKey: [String: [DegreeRequirement]] = [:]
        for section in bundle.requirementSections {
            let sectionType = normalizedDegreeTypeForStorage(section.degreeType) ?? section.degreeType
            let key = programKey(major: section.major, degreeType: sectionType, programURL: section.programURL)
            let req = bundledSectionToDegreeRequirement(section)
            requirementsByProgramKey[key, default: []].append(req)
        }

        return bundle.programs.map { program in
            let storedType = normalizedDegreeTypeForStorage(program.degreeType)
            let key = programKey(major: program.name, degreeType: storedType ?? "", programURL: program.programURL)
            let department = program.departmentNames.first ?? program.resolvedDepartment
            return (
                name: program.name,
                degreeLevel: program.degreeLevel,
                degreeType: storedType,
                isMinor: program.isMinor,
                department: department,
                url: program.programURL,
                resolvedDepartment: program.resolvedDepartment,
                resolvedCollege: program.resolvedCollege,
                mappingConfidence: program.mappingConfidence,
                mappingSource: program.mappingSource,
                requirements: requirementsByProgramKey[key],
                trackVariant: nil as String?,
                parentProgramKey: nil as String?
            )
        }
    }

    private func programKey(major: String, degreeType: String, programURL: String?) -> String {
        let canonical = DegreeTypeNormalizer.normalize(degreeType)?.storageToken ?? degreeType
        return "\(major)|\(canonical)|\(programURL ?? "")"
    }

    private func normalizedDegreeTypeForStorage(_ raw: String?) -> String? {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return DegreeTypeNormalizer.normalize(raw)?.storageToken ?? raw
    }

    private func bundledSectionToDegreeRequirement(_ section: BundledRequirementSection) -> DegreeRequirement {
        let requiredCourses = section.requiredCourses?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let requiredDetailed: [CourseDetail]? = decodeJSONList(section.requiredCoursesDetailedJSON)
        let selectFrom: [String]? = decodeJSONStringList(section.selectFromJSON)
        let selectFromDetailed: [CourseDetail]? = decodeJSONList(section.selectFromDetailedJSON)

        return DegreeRequirement(
            id: section.id,
            degreeType: section.degreeType,
            major: section.major,
            category: section.requirementCategory,
            requiredCourses: requiredCourses?.isEmpty == false ? requiredCourses : nil,
            requiredCoursesDetailed: requiredDetailed,
            creditsRequired: section.creditsRequired,
            description: section.descriptionText,
            selectFrom: selectFrom,
            selectFromDetailed: selectFromDetailed,
            selectCount: section.selectCount,
            requirementPredicate: nil
        )
    }

    private func decodeJSONStringList(_ json: String?) -> [String]? {
        guard let json, let data = json.data(using: .utf8),
              let list = try? JSONDecoder().decode([String].self, from: data),
              !list.isEmpty else { return nil }
        return list
    }

    private func decodeJSONList<T: Decodable>(_ json: String?) -> [T]? {
        guard let json, let data = json.data(using: .utf8),
              let list = try? JSONDecoder().decode([T].self, from: data),
              !list.isEmpty else { return nil }
        return list
    }
}
