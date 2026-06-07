// CatalogRelationshipStore.swift
// Feature: Catalog
// Purpose: JSON persistence for catalog graph edges (prerequisites, etc.) per school.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum CatalogRelationshipStore {
    private static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = base.appendingPathComponent("College/CatalogRelationships", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func fileURL(schoolID: String, catalogVersionID: String) -> URL {
        let safeSchool = schoolID.replacingOccurrences(of: "/", with: "_")
        let safeVersion = catalogVersionID.replacingOccurrences(of: "/", with: "_")
        return root.appendingPathComponent("\(safeSchool)__\(safeVersion).json")
    }

    static func load(schoolID: String, catalogVersionID: String) -> [CatalogRelationship] {
        let url = fileURL(schoolID: schoolID, catalogVersionID: catalogVersionID)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([CatalogRelationship].self, from: data) else {
            return []
        }
        return decoded
    }

    static func save(
        _ relationships: [CatalogRelationship],
        schoolID: String,
        catalogVersionID: String,
        merge: Bool = true
    ) {
        var combined = relationships
        if merge {
            let existing = load(schoolID: schoolID, catalogVersionID: catalogVersionID)
            var byID: [UUID: CatalogRelationship] = [:]
            for rel in existing { byID[rel.id] = rel }
            for rel in relationships { byID[rel.id] = rel }
            combined = Array(byID.values)
        }
        let url = fileURL(schoolID: schoolID, catalogVersionID: catalogVersionID)
        if let data = try? JSONEncoder().encode(combined) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

enum CatalogPrerequisiteRelationshipBuilder {
    static func relationships(
        courses: [CatalogCourse],
        catalogVersionID: String,
        codeToStableID: [String: UUID],
        ingestRunID: UUID,
        layoutProfileID: String
    ) -> [CatalogRelationship] {
        var edges: [CatalogRelationship] = []
        for course in courses {
            guard let rule = course.prerequisites else { continue }
            guard let fromID = codeToStableID[CatalogImportTransforms.normalizeCourseCode(course.courseCode)] else {
                continue
            }
            let targetCodes = extractCourseCodes(from: rule)
            for targetCode in targetCodes {
                guard let toID = codeToStableID[targetCode] else { continue }
                let provenance = CatalogProvenance(
                    sourceURL: course.previewDetailURL ?? "",
                    layoutProfileID: layoutProfileID,
                    documentNodeID: course.id,
                    catalogVersionID: catalogVersionID,
                    ingestRunID: ingestRunID
                )
                edges.append(
                    CatalogRelationship(
                        fromStableID: fromID,
                        toStableID: toID,
                        kind: .prerequisite,
                        catalogVersionID: catalogVersionID,
                        provenance: provenance
                    )
                )
            }
        }
        return edges
    }

    private static func extractCourseCodes(from rule: PrerequisiteRule) -> [String] {
        switch rule {
        case .course(let req):
            return [CatalogImportTransforms.normalizeCourseCode(req.courseCode)]
        case .and(let rules), .or(let rules):
            return rules.flatMap { extractCourseCodes(from: $0) }
        }
    }
}
