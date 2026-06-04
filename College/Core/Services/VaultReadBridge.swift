// VaultReadBridge.swift
// Feature: Core
// Purpose: Core module — VaultReadBridge.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftData

@MainActor
enum VaultReadBridge {
    static let defaultVaultListLimit = 5000

    static func documents(
        category: String? = nil,
        limit: Int = 200,
        collegePersistence: CollegePersistence = .shared
    ) -> [VaultDocument] {
        (try? collegePersistence.vaultRepository.fetchDocuments(category: category, limit: limit)) ?? []
    }

    static func allVaultDocuments(
        limit: Int = defaultVaultListLimit,
        collegePersistence: CollegePersistence = .shared
    ) -> [VaultDocument] {
        guard (try? collegePersistence.vaultRepository.hasMirroredVaultDocumentRows()) == true else { return [] }
        return (try? collegePersistence.vaultRepository.fetchAllVaultItems(limit: limit)) ?? []
    }

    static func rootFolders(
        collegePersistence: CollegePersistence = .shared
    ) -> [VaultDocument] {
        allVaultDocuments(collegePersistence: collegePersistence)
            .filter { $0.isFolder && $0.parentFolderID == nil }
            .sorted {
                $0.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
                    .localizedCaseInsensitiveCompare(
                        $1.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
                    ) == .orderedAscending
            }
    }

    static func careerResumeDocuments(
        limit: Int = 200,
        collegePersistence: CollegePersistence = .shared
    ) -> [VaultDocument] {
        documents(
            category: CollegePersistence.VaultDocumentCategory.careerResume.rawValue,
            limit: limit,
            collegePersistence: collegePersistence
        )
    }

    static func documentsLinkedToCourse(
        courseCode: String,
        collegePersistence: CollegePersistence = .shared
    ) -> [VaultDocument] {
        guard let normalized = VaultRepository.normalizedCourseCode(courseCode) else { return [] }
        guard (try? collegePersistence.vaultRepository.hasMirroredVaultDocumentRows()) == true,
              let items = try? collegePersistence.vaultRepository.fetchAllVaultItems(limit: defaultVaultListLimit) else {
            return []
        }
        return items.filter { !$0.isFolder && $0.courseCodeLinked == normalized }
    }

    static func syllabusDocuments(
        activeCourseCodes: Set<String> = [],
        collegePersistence: CollegePersistence = .shared
    ) -> [VaultDocument] {
        let syllabi = documents(
            category: CollegePersistence.VaultDocumentCategory.syllabi.rawValue,
            limit: defaultVaultListLimit,
            collegePersistence: collegePersistence
        )
        guard !activeCourseCodes.isEmpty else { return syllabi }
        return syllabi.filter { doc in
            let linked = (doc.courseCodeLinked ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            return linked.isEmpty || activeCourseCodes.contains(linked)
        }
    }
}
