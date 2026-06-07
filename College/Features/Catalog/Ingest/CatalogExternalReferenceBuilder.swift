// CatalogExternalReferenceBuilder.swift
// Feature: Catalog
// Purpose: Populate ExternalReference on courses from engine-native IDs (Tier 3).
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CatalogExternalReferenceBuilder {
    static func references(
        for course: CatalogCourse,
        engine: String,
        schoolID: String? = nil
    ) -> [ExternalReference] {
        if !course.externalReferences.isEmpty {
            return mergeArticulationReferences(
                into: course.externalReferences,
                course: course,
                schoolID: schoolID
            )
        }
        var refs: [ExternalReference] = []
        let normalizedEngine = engine.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedEngine == "moderncampus" || normalizedEngine == "pdf" {
            if let coid = course.catalogCoid?.trimmingCharacters(in: .whitespacesAndNewlines), !coid.isEmpty {
                refs.append(
                    ExternalReference(
                        system: "moderncampus",
                        externalID: coid,
                        url: course.previewDetailURL
                    )
                )
            }
        }
        if let preview = course.previewDetailURL?.trimmingCharacters(in: .whitespacesAndNewlines),
           !preview.isEmpty,
           refs.isEmpty {
            refs.append(
                ExternalReference(
                    system: normalizedEngine.isEmpty ? "catalog" : normalizedEngine,
                    externalID: course.courseCode,
                    url: preview
                )
            )
        }
        return mergeArticulationReferences(into: refs, course: course, schoolID: schoolID)
    }

    static func enriching(
        _ course: CatalogCourse,
        engine: String,
        schoolID: String? = nil
    ) -> CatalogCourse {
        let refs = references(for: course, engine: engine, schoolID: schoolID)
        guard refs != course.externalReferences else { return course }
        return CatalogCourse(
            id: course.id,
            courseCode: course.courseCode,
            title: course.title,
            description: course.description,
            credits: course.credits,
            department: course.department,
            prerequisites: course.prerequisites,
            prerequisiteText: course.prerequisiteText,
            corequisites: course.corequisites,
            typicallyOffered: course.typicallyOffered,
            catalogCoid: course.catalogCoid,
            previewDetailURL: course.previewDetailURL,
            externalReferences: refs
        )
    }

    private static func mergeArticulationReferences(
        into existing: [ExternalReference],
        course: CatalogCourse,
        schoolID: String?
    ) -> [ExternalReference] {
        guard let schoolID,
              !schoolID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return existing
        }
        let caps = CatalogManifestCapabilityStore.capabilities(forSchoolID: schoolID, format: nil)
        guard caps.supportsArticulationIngest || caps.supportsTransferEquivalencies else {
            return existing
        }
        let code = CatalogImportTransforms.normalizeCourseCode(course.courseCode)
        guard !code.isEmpty else { return existing }
        let rows = CatalogArticulationReferenceStore.rowsByCourseCode(schoolID: schoolID)[code] ?? []
        guard !rows.isEmpty else { return existing }

        var refs = existing
        var seen = Set(refs.map { "\($0.system)|\($0.externalID)" })
        for row in rows {
            let key = "\(row.system)|\(row.externalID)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            refs.append(
                ExternalReference(
                    system: row.system,
                    externalID: row.externalID,
                    url: row.url
                )
            )
        }
        return refs
    }
}
