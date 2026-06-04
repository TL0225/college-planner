// VaultDocumentMetadataAccess.swift
// Feature: Core
// Purpose: Core module — VaultDocumentMetadataAccess.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// local store-backed vault intelligence metadata (Phase 7f).
@MainActor
enum VaultDocumentMetadataAccess {
    private static var repository: VaultRepository {
        VaultRepository(context: AppDataStore.shared.profileContext)
    }

    static func document(id: UUID) -> VaultDocument? {
        try? repository.fetchDocument(id: id)
    }

    static func updateSummary(id: UUID, summary: String) {
        try? repository.updateVaultSummary(id: id, summary: summary)
        flush()
    }

    static func linkToTask(id: UUID, taskID: UUID) {
        try? repository.linkVaultDocumentToTask(id: id, taskID: taskID)
        flush()
    }

    static func updateReadingProgress(id: UUID, page: Int, totalPages: Int) {
        try? repository.updateVaultReadingProgress(id: id, page: page, totalPages: totalPages)
        flush()
    }

    static func markNeedsReview(id: UUID, courseCode: String?, confidence: Float) {
        try? repository.markVaultDocumentNeedsReview(id: id, courseCode: courseCode, confidence: confidence)
        flush()
    }

    static func confirmReview(id: UUID, courseCode: String?, category: String) {
        try? repository.confirmVaultDocumentReview(id: id, courseCode: courseCode, category: category)
        flush()
    }

    static func markDuplicate(id: UUID, versionOf primaryID: UUID) {
        try? repository.markVaultDuplicate(id: id, versionOf: primaryID)
        flush()
    }

    static func careerResumeMetadataJSON(for document: VaultDocument) -> String? {
        document.careerResumeMetadataJSON
    }

    static func setCareerResumeMetadataJSON(_ json: String?, for document: VaultDocument) {
        document.careerResumeMetadataJSON = json
        flush()
    }

    private static func flush() {
        ModelMergeCoalescer.scheduleSave(AppDataStore.shared.profileContext)
        ModelMergeCoalescer.flushNow()
        AppDataStore.shared.bumpProfileRevision()
    }
}
