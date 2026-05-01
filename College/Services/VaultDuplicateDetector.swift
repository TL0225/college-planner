import Foundation
import CryptoKit
import CoreData

// MARK: - VaultDuplicateDetector

@MainActor final class VaultDuplicateDetector {

    static let shared = VaultDuplicateDetector()

    // MARK: - Nested Types

    struct DuplicateGroup: Identifiable {
        let id: UUID = UUID()
        let files: [VaultDocumentEntity]
        let primaryID: UUID
    }

    // MARK: - Init

    private init() {}

    // MARK: - Public Methods

    func detectDuplicates() async -> [DuplicateGroup] {
        let docs = CoreDataManager.shared.vaultDocuments
        var groups: [DuplicateGroup] = []

        // MARK: Hash-based exact duplicate detection
        var hashMap: [String: [VaultDocumentEntity]] = [:]
        for doc in docs {
            if let fileURL = CoreDataManager.shared.urlForVaultDocument(doc) {
                if let hash = sha256(of: fileURL) {
                    hashMap[hash, default: []].append(doc)
                }
            }
        }

        var usedIDs: Set<UUID> = []
        for (_, groupDocs) in hashMap where groupDocs.count >= 2 {
            let primaryID = groupDocs.first?.id ?? UUID()
            let group = DuplicateGroup(files: groupDocs, primaryID: primaryID)
            groups.append(group)
            groupDocs.compactMap { $0.id }.forEach { usedIDs.insert($0) }
        }

        // MARK: Filename similarity duplicate detection (Levenshtein > 80%)
        let remaining = docs.filter { doc in
            guard let id = doc.id else { return false }
            return !usedIDs.contains(id)
        }

        var similarityGroups: [[VaultDocumentEntity]] = []
        var visitedForSimilarity: Set<UUID> = []

        for i in 0..<remaining.count {
            let docA = remaining[i]
            guard let idA = docA.id, !visitedForSimilarity.contains(idA) else { continue }
            guard let nameA = baseName(for: docA) else { continue }

            var cluster: [VaultDocumentEntity] = [docA]

            for j in (i + 1)..<remaining.count {
                let docB = remaining[j]
                guard let idB = docB.id, !visitedForSimilarity.contains(idB) else { continue }
                guard let nameB = baseName(for: docB) else { continue }

                let maxLen = max(nameA.count, nameB.count)
                if maxLen == 0 { continue }
                let dist = levenshtein(nameA, nameB)
                let similarity = 1.0 - (Double(dist) / Double(maxLen))

                if similarity > 0.80 {
                    cluster.append(docB)
                    visitedForSimilarity.insert(idB)
                }
            }

            if cluster.count >= 2 {
                visitedForSimilarity.insert(idA)
                similarityGroups.append(cluster)
            }
        }

        for cluster in similarityGroups {
            let primaryID = cluster.first?.id ?? UUID()
            let group = DuplicateGroup(files: cluster, primaryID: primaryID)
            groups.append(group)
        }

        return groups
    }

    func markDuplicate(_ doc: VaultDocumentEntity, versionOf primaryID: UUID) {
        doc.isDuplicate = true
        doc.versionOf = primaryID
        do {
            try CoreDataManager.shared.viewContext.save()
        } catch {
            print("[VaultDuplicateDetector] Failed to save markDuplicate: \(error)")
        }
    }

    // MARK: - Hashing

    func sha256(of url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Levenshtein Distance

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

    // MARK: - Private Helpers

    private func baseName(for doc: VaultDocumentEntity) -> String? {
        guard let fileName = doc.fileName, !fileName.isEmpty else { return nil }
        let url = URL(fileURLWithPath: fileName)
        return url.deletingPathExtension().lastPathComponent.lowercased()
    }
}
