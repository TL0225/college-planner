// VaultDuplicateDetector.swift
// Feature: Core
// Purpose: Core module — DuplicateGroup.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import CryptoKit
import SwiftData

// MARK: - VaultDuplicateDetector

@MainActor final class VaultDuplicateDetector {

    static let shared = VaultDuplicateDetector()

    struct DuplicateGroup: Identifiable {
        let id: UUID = UUID()
        let files: [VaultDocument]
        let primaryID: UUID
    }

    private init() {}

    func detectDuplicates(collegePersistence: CollegePersistence = .shared) async -> [DuplicateGroup] {
        let docs = VaultReadBridge.allVaultDocuments(collegePersistence: collegePersistence)
            .filter { !$0.isFolder }
        var groups: [DuplicateGroup] = []

        var hashMap: [String: [VaultDocument]] = [:]
        for doc in docs {
            if let fileURL = VaultDocumentAccess.urlForDocument(id: doc.id, collegePersistence: collegePersistence),
               let hash = sha256(of: fileURL) {
                hashMap[hash, default: []].append(doc)
            }
        }

        var usedIDs: Set<UUID> = []
        for (_, groupDocs) in hashMap where groupDocs.count >= 2 {
            let primaryID = groupDocs.first?.id ?? UUID()
            groups.append(DuplicateGroup(files: groupDocs, primaryID: primaryID))
            groupDocs.forEach { usedIDs.insert($0.id) }
        }

        let remaining = docs.filter { !usedIDs.contains($0.id) }

        var similarityGroups: [[VaultDocument]] = []
        var visitedForSimilarity: Set<UUID> = []

        for i in 0..<remaining.count {
            let docA = remaining[i]
            guard !visitedForSimilarity.contains(docA.id) else { continue }
            guard let nameA = baseName(for: docA) else { continue }

            var cluster: [VaultDocument] = [docA]

            for j in (i + 1)..<remaining.count {
                let docB = remaining[j]
                guard !visitedForSimilarity.contains(docB.id) else { continue }
                guard let nameB = baseName(for: docB) else { continue }

                let maxLen = max(nameA.count, nameB.count)
                if maxLen == 0 { continue }
                let dist = levenshtein(nameA, nameB)
                let similarity = 1.0 - (Double(dist) / Double(maxLen))

                if similarity > 0.80 {
                    cluster.append(docB)
                    visitedForSimilarity.insert(docB.id)
                }
            }

            if cluster.count >= 2 {
                visitedForSimilarity.insert(docA.id)
                similarityGroups.append(cluster)
            }
        }

        for cluster in similarityGroups {
            let primaryID = cluster.first?.id ?? UUID()
            groups.append(DuplicateGroup(files: cluster, primaryID: primaryID))
        }

        return groups
    }

    func markDuplicate(documentID: UUID, versionOf primaryID: UUID) {
        VaultDocumentMetadataAccess.markDuplicate(id: documentID, versionOf: primaryID)
    }

    func sha256(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let m = aChars.count
        let n = bChars.count

        if m == 0 { return n }
        if n == 0 { return m }

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)

        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                if aChars[i - 1] == bChars[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1]
                } else {
                    dp[i][j] = 1 + min(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1])
                }
            }
        }

        return dp[m][n]
    }

    private func baseName(for doc: VaultDocument) -> String? {
        let fileName = doc.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fileName.isEmpty else { return nil }
        let url = URL(fileURLWithPath: fileName)
        return url.deletingPathExtension().lastPathComponent.lowercased()
    }
}
