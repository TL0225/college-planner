// VaultRepository+MetadataWrites.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — VaultRepository+MetadataWrites.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension VaultRepository {
    func updateVaultSummary(id: UUID, summary: String, appendUserNotes: Bool = true) throws {
        guard let document = try fetchDocument(id: id) else { return }
        document.summaryText = summary
        if appendUserNotes {
            let existingNotes = document.userNotes ?? ""
            let aiBlock = "\n\n[AI Summary]\n\(summary)"
            if existingNotes.isEmpty {
                document.userNotes = aiBlock.trimmingCharacters(in: .newlines)
            } else if !existingNotes.contains("[AI Summary]") {
                document.userNotes = existingNotes + aiBlock
            }
        }
        ModelMergeCoalescer.scheduleSave(context)
    }

    func linkVaultDocumentToTask(id: UUID, taskID: UUID) throws {
        guard let document = try fetchDocument(id: id) else { return }
        document.linkedTaskID = taskID
        ModelMergeCoalescer.scheduleSave(context)
    }

    func updateVaultReadingProgress(id: UUID, page: Int, totalPages: Int) throws {
        guard let document = try fetchDocument(id: id) else { return }
        document.readingProgress = Int16(max(0, page))
        document.readingTotalPages = Int16(max(0, totalPages))
        ModelMergeCoalescer.scheduleSave(context)
    }

    func markVaultDocumentNeedsReview(id: UUID, courseCode: String?, confidence: Float) throws {
        guard let document = try fetchDocument(id: id) else { return }
        document.needsReview = true
        document.courseCodeLinked = Self.normalizedCourseCode(courseCode)
        document.classificationConfidence = confidence
        ModelMergeCoalescer.scheduleSave(context)
    }

    func confirmVaultDocumentReview(id: UUID, courseCode: String?, category: String) throws {
        guard let document = try fetchDocument(id: id) else { return }
        document.needsReview = false
        document.courseCodeLinked = Self.normalizedCourseCode(courseCode)
        document.category = category
        document.classificationConfidence = 1.0
        ModelMergeCoalescer.scheduleSave(context)
    }

    func markVaultDuplicate(id: UUID, versionOf primaryID: UUID) throws {
        guard let document = try fetchDocument(id: id) else { return }
        document.isDuplicate = true
        document.versionOf = primaryID
        ModelMergeCoalescer.scheduleSave(context)
    }

    func setCareerResumeMetadataJSON(id: UUID, json: String?) throws {
        guard let document = try fetchDocument(id: id) else { return }
        document.careerResumeMetadataJSON = json
        ModelMergeCoalescer.scheduleSave(context)
    }
}