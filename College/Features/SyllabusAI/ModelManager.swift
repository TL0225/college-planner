// ModelManager.swift
// Feature: SyllabusAI
// Purpose: SyllabusAI module — ModelSpec.
// Data: CollegePersistence / repositories when applicable.

import Foundation

enum ModelManagerError: LocalizedError {
    case invalidRepository
    case apiResponseInvalid
    case downloadFailed(String)
    case fileMoveFailed

    var errorDescription: String? {
        switch self {
        case .invalidRepository:
            return "Invalid model repository."
        case .apiResponseInvalid:
            return "Model metadata could not be read from Hugging Face."
        case .downloadFailed(let name):
            return "Failed to download \(name)."
        case .fileMoveFailed:
            return "Failed to store downloaded model file."
        }
    }
}

struct ModelSpec: Hashable, Sendable {
    enum Variant: String, Sendable {
        case jsonWorker_4bit
    }

    let variant: Variant
    let repoID: String
    let displayName: String

    /// Qwen 3.5 2B (4-bit) — on-device JSON worker for syllabus, assistant fallback, and background tasks.
    static let jsonWorker = ModelSpec(
        variant: .jsonWorker_4bit,
        repoID: "mlx-community/Qwen3.5-2B-4bit",
        displayName: "Qwen 3.5 2B (4-bit)"
    )
}

struct ModelFile: Sendable {
    let path: String
    let size: Int64?
}

struct ModelDownloadProgress: Sendable {
    let completedFiles: Int
    let totalFiles: Int
    let completedBytes: Int64?
    let totalBytes: Int64?

    var fractionCompleted: Double {
        if let completedBytes, let totalBytes, totalBytes > 0 {
            return Double(completedBytes) / Double(totalBytes)
        }
        if totalFiles > 0 {
            return Double(completedFiles) / Double(totalFiles)
        }
        return 0
    }
}

actor ModelManager {
    static let shared = ModelManager()

    private let fileManager = FileManager.default
    private var inFlightInstallTasks: [ModelSpec.Variant: Task<URL, Error>] = [:]

    private struct InstallMarker: Codable {
        let variant: String
        let repoID: String
        let installedAtISO8601: String
        let fileCount: Int
    }

    func modelDirectoryURL(for spec: ModelSpec) throws -> URL {
        let base = try applicationSupportModelsDirectory()
        return base.appendingPathComponent(spec.variant.rawValue, isDirectory: true)
    }

    func isModelInstalled(_ spec: ModelSpec) async -> Bool {
        do {
            let dir = try modelDirectoryURL(for: spec)
            return isValidInstalledModelDirectory(dir, spec: spec)
        } catch {
            return false
        }
    }

    func deleteModel(_ spec: ModelSpec) async throws {
        let dir = try modelDirectoryURL(for: spec)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
    }

    func installedModelSizeBytes(_ spec: ModelSpec) async -> Int64 {
        do {
            let dir = try modelDirectoryURL(for: spec)
            return directorySize(dir)
        } catch {
            return 0
        }
    }

    func ensureModelInstalled(
        _ spec: ModelSpec,
        progress: @Sendable @escaping (ModelDownloadProgress) -> Void
    ) async throws -> URL {
        let dir = try modelDirectoryURL(for: spec)
        if isValidInstalledModelDirectory(dir, spec: spec) {
            return dir
        }

        if let inFlight = inFlightInstallTasks[spec.variant] {
            return try await inFlight.value
        }

        let installTask = Task<URL, Error> {
            try await self.installModel(spec, destinationDirectory: dir, progress: progress)
        }
        inFlightInstallTasks[spec.variant] = installTask

        do {
            let installed = try await installTask.value
            inFlightInstallTasks.removeValue(forKey: spec.variant)
            return installed
        } catch {
            inFlightInstallTasks.removeValue(forKey: spec.variant)
            throw error
        }
    }

    private func installModel(
        _ spec: ModelSpec,
        destinationDirectory: URL,
        progress: @Sendable @escaping (ModelDownloadProgress) -> Void
    ) async throws -> URL {
        let parentDirectory = destinationDirectory.deletingLastPathComponent()
        let stagingDirectory = parentDirectory.appendingPathComponent("\(spec.variant.rawValue).staging-\(UUID().uuidString)", isDirectory: true)

        if fileManager.fileExists(atPath: stagingDirectory.path) {
            try? fileManager.removeItem(at: stagingDirectory)
        }
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        do {
            let files = try await fetchModelFileList(repoID: spec.repoID)
            let totalFiles = files.count
            let totalBytes = files.compactMap(\.size).reduce(Int64(0), +)
            var completedFiles = 0
            var completedBytes: Int64 = 0

            // Create all subdirectories up front (serial, fast).
            for file in files {
                let local = stagingDirectory.appendingPathComponent(file.path)
                let parent = local.deletingLastPathComponent()
                if !fileManager.fileExists(atPath: parent.path) {
                    try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
                }
            }

            // Concurrent downloads — up to 4 in flight at once.
            let maxConcurrent = 4
            var fileIndex = 0

            try await withThrowingTaskGroup(of: (String, Int64).self) { group in
                // Seed the initial batch (resolve URLs on the actor before entering tasks).
                for file in files.prefix(maxConcurrent) {
                    let remote = try huggingFaceResolveURL(repoID: spec.repoID, filePath: file.path)
                    let local = stagingDirectory.appendingPathComponent(file.path)
                    group.addTask {
                        let bytes = try await self.downloadFile(remoteURL: remote, to: local)
                        return (file.path, bytes)
                    }
                    fileIndex += 1
                }

                // As each task finishes, report progress and enqueue the next file.
                for try await (_, bytes) in group {
                    completedFiles += 1
                    completedBytes += bytes
                    progress(.init(
                        completedFiles: completedFiles,
                        totalFiles: totalFiles,
                        completedBytes: totalBytes > 0 ? completedBytes : nil,
                        totalBytes: totalBytes > 0 ? totalBytes : nil
                    ))

                    if fileIndex < files.count {
                        let file = files[fileIndex]
                        let remote = try huggingFaceResolveURL(repoID: spec.repoID, filePath: file.path)
                        let local = stagingDirectory.appendingPathComponent(file.path)
                        group.addTask {
                            let bytes = try await self.downloadFile(remoteURL: remote, to: local)
                            return (file.path, bytes)
                        }
                        fileIndex += 1
                    }
                }
            }

            try writeInstallMarker(for: spec, fileCount: files.count, in: stagingDirectory)
            guard isValidInstalledModelDirectory(stagingDirectory, spec: spec) else {
                throw ModelManagerError.downloadFailed(spec.displayName)
            }

            if fileManager.fileExists(atPath: destinationDirectory.path) {
                try fileManager.removeItem(at: destinationDirectory)
            }
            try fileManager.moveItem(at: stagingDirectory, to: destinationDirectory)

            guard isValidInstalledModelDirectory(destinationDirectory, spec: spec) else {
                throw ModelManagerError.downloadFailed(spec.displayName)
            }
            return destinationDirectory
        } catch {
            try? fileManager.removeItem(at: stagingDirectory)
            throw error
        }
    }

    // MARK: - Paths

    private func applicationSupportModelsDirectory() throws -> URL {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ModelManagerError.fileMoveFailed
        }

        let bundleID = Bundle.main.bundleIdentifier ?? "College"
        let base = appSupport.appendingPathComponent(bundleID, isDirectory: true)
        let models = base.appendingPathComponent("Models", isDirectory: true)
        if !fileManager.fileExists(atPath: models.path) {
            try fileManager.createDirectory(at: models, withIntermediateDirectories: true)
        }
        return models
    }

    // MARK: - Hugging Face API

    private struct HFModelInfo: Decodable {
        struct Sibling: Decodable {
            let rfilename: String
            let size: Int64?
        }
        let siblings: [Sibling]?
    }

    private func fetchModelFileList(repoID: String) async throws -> [ModelFile] {
        guard repoID.contains("/") else { throw ModelManagerError.invalidRepository }
        guard let url = URL(string: "https://huggingface.co/api/models/\(repoID)") else {
            throw ModelManagerError.invalidRepository
        }
        let (data, _) = try await URLSession.shared.data(from: url)

        let info = try JSONDecoder().decode(HFModelInfo.self, from: data)
        guard let siblings = info.siblings, !siblings.isEmpty else {
            throw ModelManagerError.apiResponseInvalid
        }

        // Filter out obviously non-required files.
        let ignoreExtensions = Set(["md", "txt"])
        let ignoreNames = Set(["README.md", "LICENSE", ".gitattributes"])

        let files = siblings
            .filter { sib in
                if ignoreNames.contains(sib.rfilename) { return false }
                if let ext = sib.rfilename.split(separator: ".").last.map(String.init), ignoreExtensions.contains(ext.lowercased()) {
                    return false
                }
                return true
            }
            .map { ModelFile(path: $0.rfilename, size: $0.size) }

        if files.isEmpty { throw ModelManagerError.apiResponseInvalid }
        return files
    }

    private func huggingFaceResolveURL(repoID: String, filePath: String) throws -> URL {
        guard let encoded = filePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw ModelManagerError.invalidRepository
        }
        guard let url = URL(string: "https://huggingface.co/\(repoID)/resolve/main/\(encoded)") else {
            throw ModelManagerError.invalidRepository
        }
        return url
    }

    // MARK: - Download

    private func downloadFile(remoteURL: URL, to localURL: URL) async throws -> Int64 {
        let (tmpURL, response) = try await URLSession.shared.download(from: remoteURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw ModelManagerError.downloadFailed(remoteURL.lastPathComponent)
        }

        if fileManager.fileExists(atPath: localURL.path) {
            try? fileManager.removeItem(at: localURL)
        }

        do {
            try fileManager.moveItem(at: tmpURL, to: localURL)
        } catch {
            // Fallback to copy when move across volumes fails.
            do {
                try fileManager.copyItem(at: tmpURL, to: localURL)
                try? fileManager.removeItem(at: tmpURL)
            } catch {
                throw ModelManagerError.fileMoveFailed
            }
        }

        let bytes = (try? localURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
        return bytes
    }

    private func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            total += (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
        }
        return total
    }

    private func writeInstallMarker(for spec: ModelSpec, fileCount: Int, in directory: URL) throws {
        let marker = InstallMarker(
            variant: spec.variant.rawValue,
            repoID: spec.repoID,
            installedAtISO8601: ISO8601DateFormatter().string(from: Date()),
            fileCount: fileCount
        )
        let data = try JSONEncoder().encode(marker)
        let markerURL = directory.appendingPathComponent(".install_complete.json")
        try data.write(to: markerURL, options: .atomic)
    }

    private func isValidInstalledModelDirectory(_ directory: URL, spec: ModelSpec) -> Bool {
        guard fileManager.fileExists(atPath: directory.path) else { return false }

        let markerURL = directory.appendingPathComponent(".install_complete.json")
        guard fileManager.fileExists(atPath: markerURL.path),
              let markerData = try? Data(contentsOf: markerURL),
              let marker = try? JSONDecoder().decode(InstallMarker.self, from: markerData),
              marker.variant == spec.variant.rawValue,
              marker.repoID == spec.repoID,
              marker.fileCount > 0
        else {
            return false
        }

        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return false
        }

        var hasConfigLikeFile = false
        var hasWeightsFile = false

        for case let fileURL as URL in enumerator {
            let fileName = fileURL.lastPathComponent.lowercased()
            if fileName == "config.json" || fileName == "tokenizer.json" || fileName == "tokenizer_config.json" {
                hasConfigLikeFile = true
            }
            if fileName.hasSuffix(".safetensors") || fileName.hasSuffix(".bin") {
                hasWeightsFile = true
            }
            if hasConfigLikeFile && hasWeightsFile { break }
        }

        return hasConfigLikeFile && hasWeightsFile
    }
}
