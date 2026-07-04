// CollegePersistence+Transfer.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — CollegePersistence facade for the Transfer Database.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

extension CollegePersistence {
    var transferRepository: TransferRepository {
        TransferRepository(context: profileContext)
    }

    // MARK: - Reads

    func fetchTransferEquivalencies(
        targetSchoolID: String? = nil,
        sourceSchoolID: String? = nil,
        includeArchived: Bool = false
    ) -> [TransferEquivalency] {
        (try? transferRepository.fetchEquivalencies(
            targetSchoolID: targetSchoolID,
            sourceSchoolID: sourceSchoolID,
            includeArchived: includeArchived
        )) ?? []
    }

    func transferEquivalencyDTOs(
        targetSchoolID: String? = nil,
        sourceSchoolID: String? = nil
    ) -> [TransferEquivalencyDTO] {
        let repo = transferRepository
        return fetchTransferEquivalencies(
            targetSchoolID: targetSchoolID,
            sourceSchoolID: sourceSchoolID
        ).map(repo.makeDTO(from:))
    }

    func transferProofRecords(equivalencyID: UUID) -> [TransferProofRecord] {
        (try? transferRepository.fetchProofRecords(equivalencyID: equivalencyID)) ?? []
    }

    // MARK: - Writes

    @discardableResult
    func upsertTransferEquivalencies(_ dtos: [TransferEquivalencyDTO]) -> Int {
        (try? transferRepository.upsertBatch(dtos)) ?? 0
    }

    func setTransferVerificationStatus(id: UUID, status: TransferVerificationStatus) {
        try? transferRepository.setVerificationStatus(id: id, status: status)
    }

    func setTransferConfidenceOverride(id: UUID, confidence: Int?) {
        try? transferRepository.setConfidenceOverride(id: id, confidence: confidence)
    }

    func archiveTransferEquivalency(id: UUID, archived: Bool = true) {
        try? transferRepository.archiveEquivalency(id: id, archived: archived)
    }

    func deleteTransferEquivalency(id: UUID) {
        try? transferRepository.deleteEquivalency(id: id)
    }

    @discardableResult
    func recordTransferProof(
        equivalencyID: UUID,
        proofDocumentID: UUID,
        validation: TransferProofValidationResult
    ) -> TransferProofRecord? {
        try? transferRepository.upsertProof(
            equivalencyID: equivalencyID,
            proofDocumentID: proofDocumentID,
            validation: validation
        )
    }

    func deleteTransferProof(id: UUID) {
        try? transferRepository.deleteProof(id: id)
    }
}
