// ResumeDocumentRestore.swift
// Feature: Resume
// Purpose: Hydrate a builder draft from vault resume metadata.

import Foundation

@MainActor
enum ResumeDocumentRestore {
    static func load(documentID: UUID, collegePersistence: CollegePersistence) -> ResumeDocument? {
        guard let vaultDoc = try? collegePersistence.vaultRepository.fetchDocument(id: documentID) else {
            return nil
        }

        _ = ResumeDocumentMigration.repairLegacyResumesIfNeeded(
            resumes: [vaultDoc],
            collegePersistence: collegePersistence
        )

        let meta = collegePersistence.careerResumeMetadata(for: vaultDoc)
        if let document = ResumeDocument.decode(from: meta.documentJSON) {
            return document
        }

        guard let snapshot = try? ResumeSnapshotBuilder.build(collegePersistence: collegePersistence) else {
            return nil
        }
        var document = ResumeDocument.seed(from: snapshot)
        document.id = documentID
        return document
    }
}
