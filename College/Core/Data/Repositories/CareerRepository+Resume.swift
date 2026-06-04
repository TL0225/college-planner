// CareerRepository+Resume.swift
// Feature: Core/Data
// Purpose: Core/Data persistence — — CareerResumeLibraryStats.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

// MARK: - Phase 7f career resume vault helpers

extension CareerRepository {
    struct CareerResumeLibraryStats: Equatable, Sendable {
        var versions: Int
        var tailored: Int
        var avgATS: Int?
    }

    private static let careerVaultResumesFolderIDKey = "career.vault.resumesFolderId.v1"
    private static let careerVaultResumesFolderName = "Career · Resumes"
    private static let careerResumeTextKey = "career.resumeText.v1"

    func careerResumeMetadata(for document: VaultDocument) -> CareerResumeMetadataV1 {
        guard let json = document.careerResumeMetadataJSON,
              let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(CareerResumeMetadataV1.self, from: data)
        else { return .default }
        return decoded
    }

    func setCareerResumeMetadata(_ meta: CareerResumeMetadataV1, for document: VaultDocument) throws {
        guard let data = try? JSONEncoder().encode(meta),
              let json = String(data: data, encoding: .utf8) else { return }
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
            if let score = meta.atsScorePercent {
                atsSum += score
                atsCount += 1
            }
        }
        let avg: Int? = atsCount > 0 ? Int((Double(atsSum) / Double(atsCount)).rounded()) : nil
        return CareerResumeLibraryStats(versions: versions, tailored: tailored, avgATS: avg)
    }

    @MainActor
    func scoreCareerResumeHeuristic(
        for document: VaultDocument,
        vaultRepository: VaultRepository
    ) -> Int {
        let meta = careerResumeMetadata(for: document)
        var corpusParts: [String] = [
            document.customDisplayName ?? "",
            document.fileName,
            document.tags ?? "",
            document.userNotes ?? "",
        ]
        if let role = meta.targetRole { corpusParts.append(role) }
        var corpus = corpusParts.joined(separator: " ")
        if let temp = vaultRepository.decryptedTempURLForStoredRelativePath(
            document.localRelativePath,
            displayFileName: document.fileName
        ) {
            defer { try? FileManager.default.removeItem(at: temp) }
            if let data = try? Data(contentsOf: temp),
               let text = String(data: data, encoding: .utf8) {
                corpus += " " + String(text.prefix(14_000))
            }
        }
        return Self.tokenOverlapATSPercent(baseline: careerResumeBaselineText(), resumeCorpus: corpus)
    }

    func persistCareerResumeATSScore(_ score: Int, for document: VaultDocument) throws {
        var meta = careerResumeMetadata(for: document)
        meta.atsScorePercent = min(100, max(0, score))
        meta.atsScoredAt = Date()
        try setCareerResumeMetadata(meta, for: document)
    }

    func careerResumeUsageCount(for resume: VaultDocument) -> Int {
        resume.submittedApplications?.count ?? 0
    }

    @discardableResult
    func ensureCareerResumesVaultFolder(vaultRepository: VaultRepository) throws -> UUID? {
        if let stored = UserDefaults.standard.string(forKey: Self.careerVaultResumesFolderIDKey),
           let id = UUID(uuidString: stored),
           (try? vaultRepository.fetchDocument(id: id))?.isFolder == true {
            return id
        }

        let all = try vaultRepository.fetchAllVaultItems()
        if let existing = all.first(where: {
            $0.isFolder && $0.fileName == Self.careerVaultResumesFolderName
        }) {
            UserDefaults.standard.set(existing.id.uuidString, forKey: Self.careerVaultResumesFolderIDKey)
            return existing.id
        }

        guard let folder = try vaultRepository.createVaultFolder(
            name: Self.careerVaultResumesFolderName,
            parentFolderID: nil
        ) else { return nil }
        UserDefaults.standard.set(folder.id.uuidString, forKey: Self.careerVaultResumesFolderIDKey)
        return folder.id
    }

    @MainActor
    @discardableResult
    func importCareerResume(from url: URL, vaultRepository: VaultRepository) throws -> VaultDocument? {
        let parentID = try ensureCareerResumesVaultFolder(vaultRepository: vaultRepository)
        let fileName = url.lastPathComponent

        if let parentID {
            let existing = try vaultRepository.fetchDocuments(category: VaultRepository.VaultDocumentCategory.careerResume.rawValue, limit: 500)
                .first { $0.parentFolderID == parentID && $0.fileName == fileName }
            if let existing { return existing }
        }

        try vaultRepository.addVaultDocument(
            fromSelectedURL: url,
            category: VaultRepository.VaultDocumentCategory.careerResume,
            source: "career",
            parentFolderID: parentID
        )

        return try vaultRepository.fetchDocuments(category: VaultRepository.VaultDocumentCategory.careerResume.rawValue, limit: 1).first
    }

    func careerResumeBaselineText() -> String {
        if let text = UserDefaults.standard.string(forKey: Self.careerResumeTextKey),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
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