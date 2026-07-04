// ResumeDocument.swift
// Feature: Resume
// Purpose: Persisted builder draft combining Profile snapshot, overrides, and layout.

import Foundation

enum TypstSourceMode: String, Codable, Sendable, Hashable {
    case generated
    case manual
}

struct ResumeSectionConfig: Codable, Sendable, Equatable, Hashable {
    var kind: ResumeSectionKind
    var isIncluded: Bool

    init(kind: ResumeSectionKind, isIncluded: Bool = true) {
        self.kind = kind
        self.isIncluded = isIncluded
    }
}

struct ResumeDocument: Codable, Identifiable, Sendable, Equatable {
    var id: UUID
    var title: String
    var sourceProfileID: UUID
    var baseSnapshot: ResumeSnapshot
    var style: ResumeDocumentStyle
    var sectionOrder: [ResumeSectionKind]
    var sectionConfigs: [ResumeSectionConfig]
    var fieldOverrides: [String: String]
    var typstSourceMode: TypstSourceMode
    var manualTypstSource: String?
    var templateID: String
    var updatedAt: Date

    static func seed(from snapshot: ResumeSnapshot) -> ResumeDocument {
        let defaultOrder: [ResumeSectionKind] = [
            .summary,
            .education,
            .experience,
            .projects,
            .skills,
            .achievements,
            .certifications,
            .extracurriculars,
        ]
        let title = snapshot.personal.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ResumeDocument(
            id: UUID(),
            title: title.isEmpty ? "My Resume" : title,
            sourceProfileID: snapshot.sourceProfileID,
            baseSnapshot: snapshot,
            style: .standard,
            sectionOrder: defaultOrder,
            sectionConfigs: defaultOrder.map { ResumeSectionConfig(kind: $0) },
            fieldOverrides: [:],
            typstSourceMode: .generated,
            manualTypstSource: nil,
            templateID: StandardATSTemplate.identifier,
            updatedAt: .now
        )
    }

    func fieldOverride(for key: ResumeFieldKey) -> String? {
        fieldOverrides[key.storageKey]
    }

    mutating func setFieldOverride(_ value: String?, for key: ResumeFieldKey) {
        if let value {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                fieldOverrides.removeValue(forKey: key.storageKey)
            } else {
                fieldOverrides[key.storageKey] = trimmed
            }
        } else {
            fieldOverrides.removeValue(forKey: key.storageKey)
        }
        updatedAt = .now
    }

    func isSectionIncluded(_ kind: ResumeSectionKind) -> Bool {
        guard kind != .personal else { return true }
        return sectionConfigs.first(where: { $0.kind == kind })?.isIncluded ?? sectionOrder.contains(kind)
    }

    mutating func touch() {
        updatedAt = .now
    }

    func encodedJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(from json: String?) -> ResumeDocument? {
        guard let json,
              let data = json.data(using: .utf8),
              let document = try? JSONDecoder().decode(ResumeDocument.self, from: data)
        else { return nil }
        return document
    }
}
