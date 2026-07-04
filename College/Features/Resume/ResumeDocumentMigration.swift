// ResumeDocumentMigration.swift
// Feature: Resume
// Purpose: One-time repair for legacy vault resume metadata on library open.

import Foundation

@MainActor
enum ResumeDocumentMigration {
    struct RepairResult: Sendable, Equatable {
        var repairedDocumentIDs: [UUID]
        var repairedCount: Int { repairedDocumentIDs.count }
    }

    /// Repairs legacy `CareerResumeMetadataV1` sidecars for vault resumes.
    ///
    /// 1. `buildMetadataJSON` without `documentJSON` → seed `ResumeDocument` from Profile.
    /// 2. `structuredSectionsJSON` without `canonicalProfileJSON` → map structured → canonical.
    /// 3. `ingestCompletedAt` without structured JSON → clear zombie ingest completion.
    static func repairLegacyResumesIfNeeded(
        resumes: [VaultDocument],
        collegePersistence: CollegePersistence
    ) -> RepairResult {
        var repairedIDs: [UUID] = []

        for resume in resumes {
            var meta = collegePersistence.careerResumeMetadata(for: resume)
            var changed = false

            if repairMissingDocumentJSON(meta: &meta, collegePersistence: collegePersistence) {
                changed = true
            }
            if repairMissingCanonicalProfile(meta: &meta) {
                changed = true
            }
            if repairZombieIngestCompletion(meta: &meta) {
                changed = true
            }

            guard changed else { continue }

            do {
                try collegePersistence.setCareerResumeMetadata(meta, for: resume)
                collegePersistence.bumpCareerRevision()
                repairedIDs.append(resume.id)
            } catch {
                DiagnosticsEvent.emit(
                    subsystem: .app,
                    severity: .warning,
                    code: "resume.metadataRepairFailed",
                    message: "Failed to repair resume metadata for \(resume.id.uuidString)",
                    category: "resume.migration"
                )
            }
        }

        if !repairedIDs.isEmpty {
            DiagnosticsEvent.emit(
                subsystem: .app,
                severity: .info,
                code: "analytics.resumeMetadataRepaired",
                message: "resumeMetadataRepaired count=\(repairedIDs.count)",
                category: "product.analytics"
            )
        }

        return RepairResult(repairedDocumentIDs: repairedIDs)
    }

    // MARK: - Private

    private static func repairMissingDocumentJSON(
        meta: inout CareerResumeMetadataV1,
        collegePersistence: CollegePersistence
    ) -> Bool {
        guard meta.documentJSON == nil,
              meta.buildMetadataJSON != nil,
              let buildMeta = meta.buildMetadata
        else { return false }

        guard let snapshot = try? ResumeSnapshotBuilder.build(collegePersistence: collegePersistence) else {
            return false
        }

        var document = ResumeDocument.seed(from: snapshot)
        document.id = buildMeta.snapshotID
        document.sourceProfileID = buildMeta.sourceProfileID
        document.templateID = buildMeta.templateID
        document.sectionOrder = buildMeta.sectionOrder.compactMap(ResumeSectionKind.init(rawValue:))
        document.updatedAt = buildMeta.generatedDate

        guard let json = document.encodedJSON() else { return false }
        meta.documentJSON = json
        return true
    }

    private static func repairMissingCanonicalProfile(meta: inout CareerResumeMetadataV1) -> Bool {
        guard meta.canonicalProfileJSON == nil,
              let structured = meta.structuredProfile
        else { return false }

        let canonical = ResumeCanonicalProfile.from(structured: structured)
        guard canonical.hasContent,
              let json = canonical.encodedJSON()
        else { return false }

        meta.canonicalProfileJSON = json
        return true
    }

    private static func repairZombieIngestCompletion(meta: inout CareerResumeMetadataV1) -> Bool {
        guard meta.ingestCompletedAt != nil else { return false }

        let structuredJSON = meta.structuredSectionsJSON?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard structuredJSON.isEmpty else { return false }

        meta.ingestCompletedAt = nil
        if meta.ingestFailedAt == nil {
            meta.ingestFailedAt = meta.parserScoredAt ?? Date()
        }
        return true
    }
}
