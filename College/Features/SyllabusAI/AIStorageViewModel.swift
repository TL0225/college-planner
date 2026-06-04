// AIStorageViewModel.swift
// Feature: SyllabusAI
// Purpose: SyllabusAI module — AIStorageViewModel.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import SwiftUI
import Combine

@MainActor
final class AIStorageViewModel: ObservableObject {
    @Published private(set) var isWorking: Bool = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var detail: String = ""

    @Published private(set) var installedSizeBytes: Int64 = 0
    @Published private(set) var isInstalled: Bool = false
    @Published private(set) var hasStaleInstallFiles: Bool = false

    func refreshSize(for spec: ModelSpec) async {
        let sizeBytes = await ModelManager.shared.installedModelSizeBytes(spec)
        let validInstall = await ModelManager.shared.isModelInstalled(spec)

        installedSizeBytes = sizeBytes
        isInstalled = validInstall
        hasStaleInstallFiles = sizeBytes > 0 && !validInstall
    }

    func ensureInstalled(spec: ModelSpec) async throws {
        isWorking = true
        progress = 0
        detail = "Preparing…"
        defer { isWorking = false }

        _ = try await ModelManager.shared.ensureModelInstalled(spec) { p in
            Task { @MainActor in
                self.progress = p.fractionCompleted
                self.detail = "Downloading (\(p.completedFiles)/\(p.totalFiles))"
            }
        }

        await refreshSize(for: spec)
    }

    func delete(spec: ModelSpec) async throws {
        isWorking = true
        progress = 0
        detail = "Deleting…"
        defer { isWorking = false }

        try await ModelManager.shared.deleteModel(spec)
        await refreshSize(for: spec)
    }

    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
