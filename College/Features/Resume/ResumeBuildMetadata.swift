// ResumeBuildMetadata.swift
// Feature: Resume
// Purpose: Provenance metadata for builder-generated resumes.

import CryptoKit
import Foundation

struct ResumeBuildMetadata: Codable, Sendable, Equatable, Hashable {
    var snapshotID: UUID
    var sourceProfileID: UUID
    var sectionOrder: [String]
    var templateID: String
    var generatedDate: Date
    var sourceHash: String

    static func make(
        snapshot: ResumeSnapshot,
        orderedSections: [ResumeSectionKind],
        templateID: String,
        typstSource: String
    ) -> ResumeBuildMetadata {
        let digest = SHA256.hash(data: Data(typstSource.utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return ResumeBuildMetadata(
            snapshotID: snapshot.snapshotID,
            sourceProfileID: snapshot.sourceProfileID,
            sectionOrder: orderedSections.map(\.rawValue),
            templateID: templateID,
            generatedDate: Date(),
            sourceHash: hash
        )
    }

    func encodedJSON() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
