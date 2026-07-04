// TransferRepository.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — TransferRepository (equivalencies + proof records).
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

/// Bounded local-store reads/writes for the Transfer Database (schema 1.4).
@MainActor
struct TransferRepository {
    let context: ModelContext

    // MARK: - Equivalency reads

    func fetchEquivalencies(
        targetSchoolID: String? = nil,
        sourceSchoolID: String? = nil,
        includeArchived: Bool = false,
        limit: Int = 1000,
        offset: Int = 0
    ) throws -> [TransferEquivalency] {
        let target = targetSchoolID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = sourceSchoolID?.trimmingCharacters(in: .whitespacesAndNewlines)
        var descriptor = FetchDescriptor<TransferEquivalency>(
            sortBy: [
                SortDescriptor(\.sourceCourseCode, order: .forward),
                SortDescriptor(\.targetCourseCode, order: .forward),
            ]
        )
        descriptor.fetchLimit = max(1, min(limit, 5000))
        descriptor.fetchOffset = max(0, offset)
        let rows = try context.fetch(descriptor)
        return rows.filter { row in
            if !includeArchived && row.isArchived { return false }
            if let target, !target.isEmpty, row.targetSchoolID != target { return false }
            if let source, !source.isEmpty, row.sourceSchoolID != source { return false }
            return true
        }
    }

    func fetchEquivalency(id: UUID) throws -> TransferEquivalency? {
        var descriptor = FetchDescriptor<TransferEquivalency>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func fetchEquivalency(dedupeKey: String) throws -> TransferEquivalency? {
        var descriptor = FetchDescriptor<TransferEquivalency>(
            predicate: #Predicate { $0.dedupeKey == dedupeKey }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func equivalencyCount(targetSchoolID: String? = nil) throws -> Int {
        try fetchEquivalencies(targetSchoolID: targetSchoolID, limit: 5000).count
    }

    // MARK: - Equivalency writes

    /// Insert or merge a DTO keyed on its dedupe key. Higher-tier provenance wins on conflict;
    /// equal/lower tiers refresh verification timestamps without downgrading existing facts.
    @discardableResult
    func upsert(_ dto: TransferEquivalencyDTO) throws -> TransferEquivalency {
        let key = TransferNormalization.dedupeKey(for: dto)
        if let existing = try fetchEquivalency(dedupeKey: key) {
            apply(dto, to: existing, dedupeKey: key, allowDowngrade: false)
            try saveAndBump()
            return existing
        }
        let model = TransferEquivalency(
            id: dto.id,
            sourceSchoolID: dto.sourceSchoolID,
            sourceSchoolName: dto.sourceSchoolName,
            sourceCourseCode: dto.sourceCourseCode,
            sourceCourseTitle: dto.sourceCourseTitle,
            sourceCredits: Int16(clamping: dto.sourceCredits),
            targetSchoolID: dto.targetSchoolID,
            targetSchoolName: dto.targetSchoolName,
            targetCourseCode: dto.targetCourseCode,
            targetCourseTitle: dto.targetCourseTitle,
            targetCredits: Int16(clamping: dto.targetCredits),
            equivalencyKind: dto.equivalencyKind.rawValue,
            degreeLevel: TransferNormalization.normalizeDegreeLevel(dto.degreeLevel),
            sourceTier: dto.sourceTier.rawValue,
            originIdentifier: TransferNormalization.originIdentifier(kind: dto.sourceKind, externalID: dto.externalID),
            sourceURL: dto.sourceURL,
            submittedAt: dto.submittedAt,
            lastVerifiedAt: dto.lastVerifiedAt,
            effectiveTerm: dto.effectiveTerm,
            verificationStatus: dto.verificationStatus.rawValue,
            proofDocumentID: nil,
            confidenceOverride: nil,
            dedupeKey: key,
            notes: dto.notes,
            isArchived: false
        )
        context.insert(model)
        try saveAndBump()
        return model
    }

    @discardableResult
    func upsertBatch(_ dtos: [TransferEquivalencyDTO]) throws -> Int {
        guard !dtos.isEmpty else { return 0 }
        var touched = 0
        for dto in dtos {
            let key = TransferNormalization.dedupeKey(for: dto)
            if let existing = try fetchEquivalency(dedupeKey: key) {
                apply(dto, to: existing, dedupeKey: key, allowDowngrade: false)
            } else {
                let model = TransferEquivalency(
                    id: dto.id,
                    sourceSchoolID: dto.sourceSchoolID,
                    sourceSchoolName: dto.sourceSchoolName,
                    sourceCourseCode: dto.sourceCourseCode,
                    sourceCourseTitle: dto.sourceCourseTitle,
                    sourceCredits: Int16(clamping: dto.sourceCredits),
                    targetSchoolID: dto.targetSchoolID,
                    targetSchoolName: dto.targetSchoolName,
                    targetCourseCode: dto.targetCourseCode,
                    targetCourseTitle: dto.targetCourseTitle,
                    targetCredits: Int16(clamping: dto.targetCredits),
                    equivalencyKind: dto.equivalencyKind.rawValue,
                    degreeLevel: TransferNormalization.normalizeDegreeLevel(dto.degreeLevel),
                    sourceTier: dto.sourceTier.rawValue,
                    originIdentifier: TransferNormalization.originIdentifier(kind: dto.sourceKind, externalID: dto.externalID),
                    sourceURL: dto.sourceURL,
                    submittedAt: dto.submittedAt,
                    lastVerifiedAt: dto.lastVerifiedAt,
                    effectiveTerm: dto.effectiveTerm,
                    verificationStatus: dto.verificationStatus.rawValue,
                    proofDocumentID: nil,
                    confidenceOverride: nil,
                    dedupeKey: key,
                    notes: dto.notes,
                    isArchived: false
                )
                context.insert(model)
            }
            touched += 1
        }
        try saveAndBump()
        return touched
    }

    func setVerificationStatus(id: UUID, status: TransferVerificationStatus) throws {
        guard let model = try fetchEquivalency(id: id) else { return }
        model.verificationStatus = status.rawValue
        if status == .verified {
            model.lastVerifiedAt = .now
        }
        try saveAndBump()
    }

    func setConfidenceOverride(id: UUID, confidence: Int?) throws {
        guard let model = try fetchEquivalency(id: id) else { return }
        model.confidenceOverride = confidence.map { Int16(clamping: $0) }
        try saveAndBump()
    }

    func archiveEquivalency(id: UUID, archived: Bool = true) throws {
        guard let model = try fetchEquivalency(id: id) else { return }
        model.isArchived = archived
        try saveAndBump()
    }

    func deleteEquivalency(id: UUID) throws {
        guard let model = try fetchEquivalency(id: id) else { return }
        for proof in try fetchProofRecords(equivalencyID: id) {
            context.delete(proof)
        }
        context.delete(model)
        try saveAndBump()
    }

    // MARK: - Proof CRUD

    func fetchProofRecords(equivalencyID: UUID) throws -> [TransferProofRecord] {
        var descriptor = FetchDescriptor<TransferProofRecord>(
            predicate: #Predicate { $0.equivalencyID == equivalencyID },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 50
        return try context.fetch(descriptor)
    }

    func fetchProofRecord(id: UUID) throws -> TransferProofRecord? {
        var descriptor = FetchDescriptor<TransferProofRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    @discardableResult
    func upsertProof(
        equivalencyID: UUID,
        proofDocumentID: UUID,
        validation: TransferProofValidationResult
    ) throws -> TransferProofRecord {
        let record: TransferProofRecord
        if let existing = try fetchProofRecords(equivalencyID: equivalencyID)
            .first(where: { $0.proofDocumentID == proofDocumentID }) {
            record = existing
        } else {
            record = TransferProofRecord(
                equivalencyID: equivalencyID,
                proofDocumentID: proofDocumentID,
                hasRegistrarHeader: validation.hasRegistrarHeader,
                signatureDetected: validation.signatureDetected,
                textExtractionMethod: validation.textExtractionMethod.rawValue,
                validationScore: validation.score
            )
            context.insert(record)
        }
        record.detectedUniversityName = validation.detectedUniversityName
        record.hasRegistrarHeader = validation.hasRegistrarHeader
        record.pdfProducer = validation.pdfProducer
        record.pdfCreationDate = validation.pdfCreationDate
        record.signatureDetected = validation.signatureDetected
        record.textExtractionMethod = validation.textExtractionMethod.rawValue
        record.validationScore = validation.score

        if let equivalency = try fetchEquivalency(id: equivalencyID) {
            equivalency.proofDocumentID = proofDocumentID
            if validation.isAcceptable, equivalency.verificationStatus == TransferVerificationStatus.unverified.rawValue {
                equivalency.verificationStatus = TransferVerificationStatus.pendingReview.rawValue
            }
        }
        try saveAndBump()
        return record
    }

    func deleteProof(id: UUID) throws {
        guard let record = try fetchProofRecord(id: id) else { return }
        let equivalencyID = record.equivalencyID
        context.delete(record)
        if let equivalency = try fetchEquivalency(id: equivalencyID),
           try fetchProofRecords(equivalencyID: equivalencyID).isEmpty {
            equivalency.proofDocumentID = nil
        }
        try saveAndBump()
    }

    // MARK: - Mapping

    func makeDTO(from model: TransferEquivalency) -> TransferEquivalencyDTO {
        let origin = TransferNormalization.decodeOrigin(model.originIdentifier)
        return TransferEquivalencyDTO(
            id: model.id,
            sourceSchoolID: model.sourceSchoolID,
            sourceSchoolName: model.sourceSchoolName,
            sourceCourseCode: model.sourceCourseCode,
            sourceCourseTitle: model.sourceCourseTitle,
            sourceCredits: Int(model.sourceCredits),
            targetSchoolID: model.targetSchoolID,
            targetSchoolName: model.targetSchoolName,
            targetCourseCode: model.targetCourseCode,
            targetCourseTitle: model.targetCourseTitle,
            targetCredits: Int(model.targetCredits),
            equivalencyKind: TransferEquivalencyKind(rawValue: model.equivalencyKind) ?? .direct,
            degreeLevel: model.degreeLevel,
            sourceTier: TransferSourceTier(rawValue: model.sourceTier) ?? .community,
            sourceKind: origin.kind,
            externalID: origin.externalID,
            sourceURL: model.sourceURL,
            effectiveTerm: model.effectiveTerm,
            verificationStatus: TransferVerificationStatus(rawValue: model.verificationStatus) ?? .unverified,
            notes: model.notes,
            submittedAt: model.submittedAt,
            lastVerifiedAt: model.lastVerifiedAt
        )
    }

    // MARK: - Internals

    private func apply(
        _ dto: TransferEquivalencyDTO,
        to model: TransferEquivalency,
        dedupeKey: String,
        allowDowngrade: Bool
    ) {
        let incomingTier = dto.sourceTier
        let existingTier = TransferSourceTier(rawValue: model.sourceTier) ?? .community
        let shouldReplaceCore = allowDowngrade || incomingTier.rank >= existingTier.rank

        model.lastVerifiedAt = dto.lastVerifiedAt ?? model.lastVerifiedAt ?? .now
        if dto.effectiveTerm != nil { model.effectiveTerm = dto.effectiveTerm }
        if model.notes == nil { model.notes = dto.notes }

        guard shouldReplaceCore else { return }
        model.sourceSchoolName = dto.sourceSchoolName
        model.sourceCourseTitle = dto.sourceCourseTitle ?? model.sourceCourseTitle
        model.sourceCredits = Int16(clamping: dto.sourceCredits)
        model.targetSchoolName = dto.targetSchoolName
        model.targetCourseTitle = dto.targetCourseTitle ?? model.targetCourseTitle
        model.targetCredits = Int16(clamping: dto.targetCredits)
        model.equivalencyKind = dto.equivalencyKind.rawValue
        model.sourceTier = dto.sourceTier.rawValue
        model.originIdentifier = TransferNormalization.originIdentifier(kind: dto.sourceKind, externalID: dto.externalID)
        model.sourceURL = dto.sourceURL ?? model.sourceURL
        model.dedupeKey = dedupeKey
        // Verified facts should not silently regress to unverified on a lower-signal refresh.
        if dto.verificationStatus != .unverified {
            model.verificationStatus = dto.verificationStatus.rawValue
        }
    }

    private func saveAndBump() throws {
        ModelMergeCoalescer.scheduleSave(context)
        ModelMergeCoalescer.flushNow()
        CollegePersistence.shared.bumpTransferRevision()
    }
}
