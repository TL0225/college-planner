// CareerRepository+Resume.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CareerResumeLibraryStats.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

// MARK: - Phase 7f career resume vault helpers

enum CareerResumeMetadataError: Error, Sendable {
    case encodeFailed
}

extension CareerRepository {
    struct CareerResumeLibraryStats: Equatable, Sendable {
        var versions: Int
        var tailored: Int
        var avgParserHealth: Int?

        var avgATS: Int? { avgParserHealth }
    }

    private static let careerVaultResumesFolderIDKey = "career.vault.resumesFolderId.v1"
    private static let careerVaultRootFolderName = "Career"
    private static let careerVaultResumesFolderName = "Resumes"
    /// Pre-nesting flat folder name; migrated into `Career/Resumes` on first access.
    private static let legacyCareerVaultResumesFolderName = "Career · Resumes"

    func careerResumeMetadata(for document: VaultDocument) -> CareerResumeMetadataV1 {
        guard let json = document.careerResumeMetadataJSON,
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(CareerResumeMetadataV1.self, from: data)
        else { return .default }
        return decoded
    }

    func setCareerResumeMetadata(_ meta: CareerResumeMetadataV1, for document: VaultDocument) throws {
        let data = try JSONEncoder().encode(meta)
        guard let json = String(data: data, encoding: .utf8) else {
            throw CareerResumeMetadataError.encodeFailed
        }
        document.careerResumeMetadataJSON = json
        ModelMergeCoalescer.scheduleSave(context)
    }

    func setCareerResumeFavorite(_ favorite: Bool, for document: VaultDocument) throws {
        document.isFavorite = favorite
        ModelMergeCoalescer.scheduleSave(context)
    }

    func careerResumeLibraryStats(for documents: [VaultDocument]) -> CareerResumeLibraryStats {
        let versions = documents.count
        var tailored = 0
        var atsSum = 0
        var atsCount = 0
        for doc in documents {
            let meta = careerResumeMetadata(for: doc)
            if meta.kind == .tailored { tailored += 1 }
            if let score = meta.parserHealthPercent {
                atsSum += score
                atsCount += 1
            }
        }
        let avg: Int? = atsCount > 0 ? Int((Double(atsSum) / Double(atsCount)).rounded()) : nil
        return CareerResumeLibraryStats(versions: versions, tailored: tailored, avgParserHealth: avg)
    }

    @MainActor
    func scoreCareerResumeHeuristic(
        for document: VaultDocument,
        vaultRepository: VaultRepository
    ) async -> Int {
        let meta = careerResumeMetadata(for: document)
        var corpusParts: [String] = [
            document.customDisplayName ?? "",
            document.fileName,
            document.tags ?? "",
            document.userNotes ?? "",
        ]
        if let role = meta.targetRole { corpusParts.append(role) }
        var corpus = corpusParts.joined(separator: " ")
        if let temp = await vaultRepository.decryptedTempURLForStoredRelativePath(
            document.localRelativePath,
            displayFileName: document.fileName
        ) {
            defer { try? FileManager.default.removeItem(at: temp) }
            let extracted = await CareerResumeTextExtractor.extract(from: temp)
            let plain = extracted.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !plain.isEmpty {
                corpus += " " + String(plain.prefix(14_000))
            }
        }
        return Self.tokenOverlapATSPercent(baseline: careerResumeBaselineText(), resumeCorpus: corpus)
    }

    func persistCareerResumeParserHealth(_ score: Int, for document: VaultDocument) throws {
        var meta = careerResumeMetadata(for: document)
        meta.parserHealthPercent = min(100, max(0, score))
        meta.parserScoredAt = Date()
        try setCareerResumeMetadata(meta, for: document)
    }

    func persistCareerResumeATSScore(_ score: Int, for document: VaultDocument) throws {
        try persistCareerResumeParserHealth(score, for: document)
    }

    @MainActor
    func careerResumePlainText(
        for document: VaultDocument,
        vaultRepository: VaultRepository
    ) async -> String {
        guard let temp = await vaultRepository.decryptedTempURLForStoredRelativePath(
            document.localRelativePath,
            displayFileName: document.fileName
        ) else { return "" }
        defer { try? FileManager.default.removeItem(at: temp) }
        let result = await CareerResumeTextExtractor.extract(from: temp)
        return result.plainText
    }

    func careerResumeUsageCount(for resume: VaultDocument) -> Int {
        resume.submittedApplications?.count ?? 0
    }

    /// Ensures the nested `Career/Resumes` vault folder hierarchy exists, migrating any
    /// legacy flat `Career · Resumes` folder (and its contents) into it. Returns the
    /// identifier of the `Resumes` folder that resume documents are parented to.
    @discardableResult
    func ensureCareerResumesVaultFolder(vaultRepository: VaultRepository) throws -> UUID? {
        var all = try vaultRepository.fetchAllVaultItems()

        // Top-level "Career" folder.
        let careerFolderID: UUID
        if let existingCareer = all.first(where: {
            $0.isFolder && $0.parentFolderID == nil && $0.fileName == Self.careerVaultRootFolderName
        }) {
            careerFolderID = existingCareer.id
        } else {
            guard let careerFolder = try vaultRepository.createVaultFolder(
                name: Self.careerVaultRootFolderName,
                parentFolderID: nil
            ) else { return nil }
            careerFolderID = careerFolder.id
            all = try vaultRepository.fetchAllVaultItems()
        }

        // Nested "Resumes" folder inside "Career". Prefer the stored identifier when it
        // still resolves to a folder living under the Career parent.
        let resumesFolderID: UUID
        if let stored = UserDefaults.standard.string(forKey: Self.careerVaultResumesFolderIDKey),
           let id = UUID(uuidString: stored),
           let storedFolder = try? vaultRepository.fetchDocument(id: id),
           storedFolder.isFolder,
           storedFolder.parentFolderID == careerFolderID {
            resumesFolderID = id
        } else if let existingResumes = all.first(where: {
            $0.isFolder && $0.parentFolderID == careerFolderID && $0.fileName == Self.careerVaultResumesFolderName
        }) {
            resumesFolderID = existingResumes.id
        } else {
            guard let resumesFolder = try vaultRepository.createVaultFolder(
                name: Self.careerVaultResumesFolderName,
                parentFolderID: careerFolderID
            ) else { return nil }
            resumesFolderID = resumesFolder.id
        }

        // Migrate any pre-nesting flat "Career · Resumes" folder into Career/Resumes.
        let legacyFolders = all.filter {
            $0.isFolder
                && $0.fileName == Self.legacyCareerVaultResumesFolderName
                && $0.id != resumesFolderID
        }
        for legacy in legacyFolders {
            let children = all.filter { $0.parentFolderID == legacy.id }
            for child in children {
                try? vaultRepository.moveVaultDocument(id: child.id, toFolderID: resumesFolderID)
            }
            try? vaultRepository.deleteVaultFolder(id: legacy.id, includeContents: false)
        }

        UserDefaults.standard.set(resumesFolderID.uuidString, forKey: Self.careerVaultResumesFolderIDKey)
        return resumesFolderID
    }

    @MainActor
    @discardableResult
    func importCareerResume(from url: URL, vaultRepository: VaultRepository) async throws -> VaultDocument? {
        let parentID = try ensureCareerResumesVaultFolder(vaultRepository: vaultRepository)
        let fileName = url.lastPathComponent

        if let parentID {
            let existing = try vaultRepository.fetchDocuments(category: VaultRepository.VaultDocumentCategory.careerResume.rawValue, limit: 500)
                .first { $0.parentFolderID == parentID && $0.fileName == fileName }
            if let existing {
                try await vaultRepository.replaceVaultDocumentContent(documentID: existing.id, fromSelectedURL: url)
                var meta = careerResumeMetadata(for: existing)
                meta.parsedTextHash = nil
                meta.structuredSectionsJSON = nil
                meta.ingestCompletedAt = nil
                meta.ingestFailedAt = nil
                meta.parserIssuesJSON = nil
                meta.parserHealthPercent = nil
                meta.detectedDomainsJSON = nil
                meta.staleSkillsJSON = nil
                try setCareerResumeMetadata(meta, for: existing)
                return existing
            }
        }

        return try await vaultRepository.addVaultDocument(
            fromSelectedURL: url,
            category: VaultRepository.VaultDocumentCategory.careerResume,
            source: "career",
            parentFolderID: parentID
        )
    }

    func careerResumeBaselineText() -> String {
        let repo = ProfileRepository(context: context)
        guard let profile = try? repo.fetchPrimaryProfile() else { return "" }
        let snippets = (profile.experiences ?? [])
            .compactMap { exp -> String? in
                let title = (exp.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let details = (exp.descriptionText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty || !details.isEmpty else { return nil }
                return [title, details].filter { !$0.isEmpty }.joined(separator: ": ")
            }
            .sorted()
        return snippets.joined(separator: "\n")
    }

    private static func tokenOverlapATSPercent(baseline: String, resumeCorpus: String) -> Int {
        let baselineLower = baseline.lowercased()
        let stop: Set<String> = [
            "that", "this", "with", "from", "your", "have", "will", "been", "were", "their", "what", "when", "which",
            "about", "into", "more", "than", "then", "some", "such", "other", "also", "only", "very", "just", "like",
            "code", "work", "team", "using", "skills", "experience", "years", "able", "make", "each", "most", "many"
        ]
        func tokens(_ s: String) -> [String] {
            s.split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count > 3 && !stop.contains($0.lowercased()) }
        }
        let resumeToks = Set(tokens(resumeCorpus.lowercased()))
        guard !resumeToks.isEmpty else { return 48 }
        var hits = 0
        for t in resumeToks where baselineLower.contains(t) {
            hits += 1
        }
        return min(100, Int((Double(hits) / Double(resumeToks.count) * 100).rounded()))
    }
}