// CatalogPDFIngestPersistence.swift
// Feature: Catalog
// Purpose: Persist PDF Document IR, entity identities, and provenance-backed program rows.
// Data: CollegePersistence / repositories when applicable.

import Foundation

@MainActor
enum CatalogPDFIngestPersistence {
    typealias MajorRow = (
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
        sourceCatalogCatoid: String?,
        trackVariant: String?,
        parentProgramKey: String?,
        catalogStableID: UUID?,
        provenanceJSON: String?
    )

    static func catalogVersion(for manifest: SchoolManifest) -> CatalogVersion {
        CatalogVersion.resolve(school: manifest, segment: .manifestOnly)
    }

    static func layoutProfileID(for manifest: SchoolManifest, documentIR: CatalogDocumentIR?) -> String {
        documentIR?.layoutProfileID ?? "pdf-\(manifest.id)"
    }

    static func persistDocumentIRTrack(
        extractionResult: CatalogPDFIngestOutput,
        manifest: SchoolManifest,
        programs: [ScrapedProgram],
        requirements: [DegreeRequirement],
        ingestRunID: UUID,
        collegePersistence: CollegePersistence
    ) async throws {
        guard CatalogPlatformFlags.documentIREnabled else { return }

        let schoolID = manifest.id
        let catalogVersion = catalogVersion(for: manifest)
        let layoutProfileID = layoutProfileID(for: manifest, documentIR: extractionResult.documentIR)

        if let ir = extractionResult.documentIR {
            CatalogDocumentIRStore.save(ir, schoolID: schoolID, catalogVersionID: catalogVersion.id)
        }

        var entityIdentities: [CatalogEntityIdentity] = []
        if let repo = AppDataStore.shared.catalogRepository,
           let university = try? repo.fetchUniversity(named: manifest.name) {
            entityIdentities = (try? CatalogIngestPersistenceHelpers.loadMergedIdentities(
                repo: repo,
                universityID: university.id,
                schoolID: schoolID,
                catalogVersionID: catalogVersion.id
            )) ?? CatalogEntityIdentityStore.load(schoolID: schoolID, catalogVersionID: catalogVersion.id)
        } else {
            entityIdentities = CatalogEntityIdentityStore.load(schoolID: schoolID, catalogVersionID: catalogVersion.id)
        }
        let identitiesBeforeIngest = entityIdentities

        let rows = buildMajorRows(
            programs: programs,
            requirements: requirements,
            catalogVersionID: catalogVersion.id,
            documentIR: extractionResult.documentIR,
            layoutProfileID: layoutProfileID,
            ingestRunID: ingestRunID,
            entityIdentities: &entityIdentities
        )

        guard !rows.isEmpty else { return }

        try CatalogBackgroundSyncRunner.saveChunkedMajorsWithCatoid(
            rows,
            for: manifest.name,
            schoolID: schoolID,
            collegePersistence: collegePersistence
        )

        CatalogIngestPersistenceHelpers.persistIdentities(
            entityIdentities,
            schoolID: schoolID,
            catalogVersionID: catalogVersion.id
        )

        let structuralDiff = CatalogStructuralDiffEngine.diff(
            schoolID: schoolID,
            catalogVersionID: catalogVersion.id,
            previous: identitiesBeforeIngest,
            current: entityIdentities
        )
        if structuralDiff.hasChanges {
            CatalogStructuralDiffStore.save(structuralDiff)
        }
    }

    static func persistCourseMetadataIfNeeded(
        courses: [CatalogCourse],
        manifest: SchoolManifest,
        documentIR: CatalogDocumentIR?,
        ingestRunID: UUID
    ) async throws {
        guard CatalogPlatformFlags.documentIREnabled, !courses.isEmpty else { return }
        let catalogVersion = catalogVersion(for: manifest)
        let layoutProfileID = layoutProfileID(for: manifest, documentIR: documentIR)
        let identities = CatalogEntityIdentityStore.load(
            schoolID: manifest.id,
            catalogVersionID: catalogVersion.id
        )
        try await CourseLeafCatalogIngestAdapter.persistCourseMetadata(
            courses: courses,
            manifest: manifest,
            schoolID: manifest.id,
            catalogVersionID: catalogVersion.id,
            layoutProfileID: layoutProfileID,
            ingestRunID: ingestRunID,
            existingIdentities: identities
        )
    }

    static func buildMajorRows(
        programs: [ScrapedProgram],
        requirements: [DegreeRequirement],
        catalogVersionID: String,
        documentIR: CatalogDocumentIR?,
        layoutProfileID: String,
        ingestRunID: UUID,
        entityIdentities: inout [CatalogEntityIdentity]
    ) -> [MajorRow] {
        programs.map { program in
            let isMinor = program.type.lowercased().contains("minor")
            let degreeTypeTrimmed = program.degreeType?.trimmingCharacters(in: .whitespacesAndNewlines)
            let degreeType = (degreeTypeTrimmed?.isEmpty ?? true) ? nil : degreeTypeTrimmed
            let degreeLevel = DegreeConfiguration.level(for: degreeType ?? "") ?? DegreeConfiguration.undergraduate

            let deptTrimmed = program.department?.trimmingCharacters(in: .whitespacesAndNewlines)
            let dept = (deptTrimmed?.isEmpty ?? true) ? nil : deptTrimmed

            let url = program.url.trimmingCharacters(in: .whitespacesAndNewlines)
            let requirementsForProgram = requirements.filter {
                $0.major.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(program.name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
            }

            let (stableID, identity) = CatalogIngestPersistenceHelpers.resolveProgramStableID(
                program: program,
                catalogVersionID: catalogVersionID,
                existing: entityIdentities
            )
            entityIdentities.append(identity)

            let provenance = CatalogProvenance(
                sourceURL: url.isEmpty ? (documentIR?.nodes.first?.sourceURL ?? "") : url,
                layoutProfileID: layoutProfileID,
                documentNodeID: documentNodeID(for: program, in: documentIR) ?? stableID,
                catalogVersionID: catalogVersionID,
                ingestRunID: ingestRunID
            )

            return (
                name: program.name,
                degreeLevel: degreeLevel,
                degreeType: degreeType,
                isMinor: isMinor,
                department: dept,
                url: url,
                resolvedDepartment: nil,
                resolvedCollege: nil,
                mappingConfidence: documentIR.map { $0.layoutConfidence.score },
                mappingSource: "pdf-block-classifier",
                requirements: requirementsForProgram.isEmpty ? nil : requirementsForProgram,
                sourceCatalogCatoid: nil,
                trackVariant: nil,
                parentProgramKey: nil,
                catalogStableID: stableID,
                provenanceJSON: CatalogIngestPersistenceHelpers.encodeProvenanceJSON(provenance)
            )
        }
    }

    private static func documentNodeID(for program: ScrapedProgram, in ir: CatalogDocumentIR?) -> UUID? {
        guard let ir else { return nil }
        let normalizedName = program.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let match = ir.nodes.first(where: { node in
            guard node.kind == .programBlock else { return false }
            guard let text = node.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  !text.isEmpty else { return false }
            return text.contains(normalizedName) || normalizedName.contains(text)
        }) {
            return match.id
        }
        return ir.nodes.first(where: { $0.kind == .programBlock })?.id
    }
}
