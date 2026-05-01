import Foundation
import SwiftUI
import Combine

// MARK: - VaultStorageAnalytics

@MainActor
final class VaultStorageAnalytics: ObservableObject {

    static let shared = VaultStorageAnalytics()

    // MARK: - Nested Types

    struct CourseStorageStat: Identifiable {
        let id: String           // course code or "Other"
        let totalBytes: Int64
        let fileCount: Int
        let percentageOfTotal: Double
    }

    struct CategoryStorageStat: Identifiable {
        let id: String
        let category: String
        let totalBytes: Int64
        let fileCount: Int
        let percentageOfTotal: Double
    }

    // MARK: - Published Properties

    @Published var courseStats: [CourseStorageStat] = []
    @Published var categoryStats: [CategoryStorageStat] = []
    @Published var totalVaultBytes: Int64 = 0
    @Published var staleFileBytes: Int64 = 0
    @Published var isRefreshing: Bool = false

    // MARK: - Init

    private init() {}

    // MARK: - Computed Properties

    var topStaleFiles: [VaultDocumentEntity] {
        let docs = CoreDataManager.shared.vaultDocuments
        return staleFiles(from: docs)
            .sorted { $0.fileSizeBytes > $1.fileSizeBytes }
            .prefix(5)
            .map { $0 }
    }

    // MARK: - Public Methods

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        let docs = CoreDataManager.shared.vaultDocuments

        // Total bytes
        let total: Int64 = docs.reduce(0) { $0 + $1.fileSizeBytes }
        totalVaultBytes = total

        // Stale file bytes
        let stale = staleFiles(from: docs)
        staleFileBytes = stale.reduce(0) { $0 + $1.fileSizeBytes }

        // Course stats
        var courseMap: [String: (bytes: Int64, count: Int)] = [:]
        for doc in docs {
            let key = (doc.courseCodeLinked?.isEmpty == false) ? doc.courseCodeLinked! : "Other"
            let existing = courseMap[key] ?? (0, 0)
            courseMap[key] = (existing.bytes + doc.fileSizeBytes, existing.count + 1)
        }
        courseStats = courseMap.map { key, value in
            CourseStorageStat(
                id: key,
                totalBytes: value.bytes,
                fileCount: value.count,
                percentageOfTotal: total > 0 ? Double(value.bytes) / Double(total) * 100.0 : 0
            )
        }.sorted { $0.totalBytes > $1.totalBytes }

        // Category stats
        var categoryMap: [String: (bytes: Int64, count: Int)] = [:]
        for doc in docs {
            let key = (doc.category?.isEmpty == false) ? doc.category! : CoreDataManager.VaultDocumentCategory.other.rawValue
            let existing = categoryMap[key] ?? (0, 0)
            categoryMap[key] = (existing.bytes + doc.fileSizeBytes, existing.count + 1)
        }
        categoryStats = categoryMap.map { key, value in
            CategoryStorageStat(
                id: key,
                category: key,
                totalBytes: value.bytes,
                fileCount: value.count,
                percentageOfTotal: total > 0 ? Double(value.bytes) / Double(total) * 100.0 : 0
            )
        }.sorted { $0.totalBytes > $1.totalBytes }
    }

    // MARK: - Stale File Detection

    func staleFiles(from docs: [VaultDocumentEntity]) -> [VaultDocumentEntity] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return docs.filter { doc in
            guard let lastOpened = doc.lastOpenedAt else { return true }
            return lastOpened < cutoff
        }
    }

    // MARK: - Formatting

    func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
