// CommunityTransferImportService.swift
// Feature: Transfer
// Purpose: Transfer Database — decode/sanitize/export community-contributed equivalencies.
// Data: Pure (de)serialization; importing into the store happens via TransferCoordinator.

import Foundation

/// Reads and normalizes community-contributed transfer datasets and exports local ones for sharing.
struct CommunityTransferImportService {
    let fixtureResource: String

    init(fixtureResource: String = "community_sample") {
        self.fixtureResource = fixtureResource
    }

    // MARK: - Decode

    static func decode(data: Data) throws -> [TransferEquivalencyDTO] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let payload = try? decoder.decode(TransferCommunityPayload.self, from: data) {
            return payload.equivalencies
        }
        do {
            return try decoder.decode([TransferEquivalencyDTO].self, from: data)
        } catch {
            throw TransferError.parsing(error.localizedDescription)
        }
    }

    func decode(fileURL: URL) throws -> [TransferEquivalencyDTO] {
        let needsScope = fileURL.startAccessingSecurityScopedResource()
        defer { if needsScope { fileURL.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw TransferError.parsing(error.localizedDescription)
        }
        return Self.sanitizedForImport(try Self.decode(data: data))
    }

    func loadBundledFixture(bundle: Bundle = .main) throws -> [TransferEquivalencyDTO] {
        guard let url = bundle.url(forResource: fixtureResource, withExtension: "json") else {
            throw TransferError.fixtureNotFound("\(fixtureResource).json")
        }
        return Self.sanitizedForImport(try Self.decode(data: try Data(contentsOf: url)))
    }

    // MARK: - Sanitize

    /// Community imports can never assert an official tier or a verified status; downgrade them
    /// so confidence scoring treats them as corroborating-but-unconfirmed evidence.
    static func sanitizedForImport(_ dtos: [TransferEquivalencyDTO]) -> [TransferEquivalencyDTO] {
        dtos.compactMap { dto in
            let source = dto.sourceCourseCode.trimmingCharacters(in: .whitespacesAndNewlines)
            let target = dto.targetCourseCode.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty, !target.isEmpty,
                  !dto.sourceSchoolID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !dto.targetSchoolID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            var copy = dto
            copy.id = UUID()
            copy.sourceKind = .communityImport
            copy.sourceTier = dto.sourceTier == .communityVerified ? .communityVerified : .community
            if copy.verificationStatus == .verified {
                copy.verificationStatus = .pendingReview
            }
            copy.lastVerifiedAt = nil
            return copy
        }
    }

    // MARK: - Export

    func export(_ dtos: [TransferEquivalencyDTO]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let payload = TransferCommunityPayload(equivalencies: dtos)
        return try encoder.encode(payload)
    }
}
