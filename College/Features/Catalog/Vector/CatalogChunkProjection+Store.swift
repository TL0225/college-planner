// CatalogChunkProjection+Store.swift
// Feature: Catalog
// Purpose: Catalog module — CatalogChunkProjection+Store.
// Data: CollegePersistence / repositories when applicable.

import CryptoKit
import Foundation
import SwiftData

extension CatalogChunkProjection {
    static func chunks(from course: CourseCatalog) -> [IndexedChunk] {
        guard let uni = course.university else { return [] }
        let uniID = uni.id
        let base = projectCoursePlainText(course: course)
        guard !base.isEmpty else { return [] }
        let parts = AssistantPolicyChunker.markdownChunks(text: base, targetCharacters: 1_500, overlapRatio: 0.12)
        let code = course.courseCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return parts.enumerated().map { index, text in
            let hash = contentHash(for: text)
            let chunkId = "course:\(course.id.uuidString)#\(index)"
            let meta: [String: Any] = [
                "type": "course",
                "courseCode": code,
                "chunkIndex": index,
                "catalogEntityId": course.id.uuidString,
            ]
            let metaJSON = (try? JSONSerialization.data(withJSONObject: meta))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            return IndexedChunk(
                chunkId: chunkId,
                universityID: uniID,
                sourceKind: "course",
                ftsBody: text,
                courseCode: code.isEmpty ? nil : code,
                programURL: nil,
                requirementCategory: nil,
                catalogScope: "",
                metadataJSON: metaJSON,
                contentHash: hash
            )
        }
    }

    static func chunks(from requirement: CatalogDegreeRequirement) -> [IndexedChunk] {
        guard let uni = requirement.university else { return [] }
        let uniID = uni.id
        let base = projectDegreePlainText(requirement: requirement)
        guard !base.isEmpty else { return [] }
        let parts = AssistantPolicyChunker.markdownChunks(text: base, targetCharacters: 1_500, overlapRatio: 0.12)
        let category = requirement.requirementCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        let major = requirement.major.trimmingCharacters(in: .whitespacesAndNewlines)
        return parts.enumerated().map { index, text in
            let hash = contentHash(for: text)
            let chunkId = "degreq:\(requirement.id.uuidString)#\(index)"
            let meta: [String: Any] = [
                "type": "degree_requirement",
                "major": major,
                "requirementCategory": category,
                "chunkIndex": index,
                "entityId": requirement.id.uuidString,
            ]
            let metaJSON = (try? JSONSerialization.data(withJSONObject: meta))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            return IndexedChunk(
                chunkId: chunkId,
                universityID: uniID,
                sourceKind: "degree_requirement",
                ftsBody: text,
                courseCode: nil,
                programURL: nil,
                requirementCategory: category.isEmpty ? nil : category,
                catalogScope: "",
                metadataJSON: metaJSON,
                contentHash: hash
            )
        }
    }

    static func chunks(from policy: CatalogPolicyDocument) -> [IndexedChunk] {
        guard let uni = policy.university else { return [] }
        let uniID = uni.id
        let body = policy.bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return [] }
        let nav = policy.navTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = policy.sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let catoid = policy.catoid.trimmingCharacters(in: .whitespacesAndNewlines)
        let scope = policy.catalogScope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var lines: [String] = []
        if !nav.isEmpty { lines.append("Policy page: \(nav)") }
        lines.append("Catalog policy:")
        lines.append(body)
        let ftsBody = lines.joined(separator: "\n")
        guard !ftsBody.isEmpty else { return [] }

        let hash = contentHash(for: ftsBody)
        let chunkId = "policy:\(policy.id.uuidString)"
        let meta: [String: Any] = [
            "type": "catalog_policy",
            "catalogScope": scope.isEmpty ? "" : scope,
            "catoid": catoid,
            "sourceURL": url,
            "navTitle": nav,
            "entityId": policy.id.uuidString,
        ]
        let metaJSON = (try? JSONSerialization.data(withJSONObject: meta))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return [
            IndexedChunk(
                chunkId: chunkId,
                universityID: uniID,
                sourceKind: "catalog_policy",
                ftsBody: ftsBody,
                courseCode: nil,
                programURL: url.isEmpty ? nil : url,
                requirementCategory: nil,
                catalogScope: scope,
                metadataJSON: metaJSON,
                contentHash: hash
            ),
        ]
    }

    // MARK: - Private

    private static func projectCoursePlainText(course: CourseCatalog) -> String {
        let code = course.courseCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = course.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let dept = (course.department ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let desc = (course.descriptionText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        var lines: [String] = []
        lines.append("Course \(code): \(title)")
        if !dept.isEmpty { lines.append("Department: \(dept)") }
        lines.append("Credits: \(course.credits)")
        if !desc.isEmpty { lines.append("Description: \(desc)") }
        return lines.joined(separator: "\n")
    }

    private static func projectDegreePlainText(requirement: CatalogDegreeRequirement) -> String {
        let major = requirement.major.trimmingCharacters(in: .whitespacesAndNewlines)
        let degType = requirement.degreeType.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = requirement.requirementCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        let desc = (requirement.descriptionText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        var lines: [String] = []
        lines.append("Program: \(major) (\(degType))")
        lines.append("Requirement block: \(category)")
        if requirement.creditsRequired != 0 {
            lines.append("Credits required (block): \(requirement.creditsRequired)")
        }
        if !desc.isEmpty { lines.append("Description: \(desc)") }
        return lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n")
    }
}
