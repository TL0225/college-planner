// VaultSemesterArchive.swift
// Feature: Core
// Purpose: Core module — ArchiveError.
// Data: CollegePersistence / repositories when applicable.

import Foundation

// MARK: - VaultSemesterArchive

actor VaultSemesterArchive {

    static let shared = VaultSemesterArchive()

    private init() {}

    // MARK: - Computed Properties

    var archiveFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/College/Archive", isDirectory: true)
    }

    // MARK: - Semester Change Detection

    /// Reads the current and last-archived semester labels from UserDefaults.
    /// If they differ and a previous semester exists, archives the old semester.
    func checkForSemesterChange() async {
        let current = UserDefaults.standard.string(forKey: "currentSemesterLabel") ?? "Current Semester"
        guard let lastArchived = UserDefaults.standard.string(forKey: "lastArchivedSemester") else {
            // Nothing archived yet — just record current as the baseline.
            UserDefaults.standard.set(current, forKey: "lastArchivedSemester")
            return
        }
        guard lastArchived != current else { return }
        do {
            try await archiveSemester(lastArchived)
        } catch {
            await AppNotificationCenter.shared.post(
                kind: .error,
                title: "Archive Failed",
                message: "Could not archive \(lastArchived): \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Archiving

    /// Creates a zip of the semester folder under ~/Documents/College/{semesterLabel}/,
    /// saves it to the archive folder, removes the source, and posts a success notification.
    func archiveSemester(_ semesterLabel: String) async throws {
        let collegeRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/College", isDirectory: true)
        let sourceFolder = collegeRoot.appendingPathComponent(semesterLabel, isDirectory: true)
        let destZip = archiveFolder.appendingPathComponent("\(semesterLabel).zip")

        guard FileManager.default.fileExists(atPath: sourceFolder.path) else {
            throw ArchiveError.sourceFolderNotFound(sourceFolder.path)
        }

        try FileManager.default.createDirectory(at: archiveFolder, withIntermediateDirectories: true)

        try runProcess(
            launchPath: "/usr/bin/ditto",
            arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent",
                        sourceFolder.path, destZip.path]
        )

        try FileManager.default.removeItem(at: sourceFolder)

        UserDefaults.standard.set(semesterLabel, forKey: "lastArchivedSemester")

        await AppNotificationCenter.shared.post(
            kind: .success,
            title: "Semester Archived",
            message: "\(semesterLabel) archived to ~/Documents/College/Archive/",
            isDismissible: true,
            autoDismissAfter: 8
        )
    }

    // MARK: - Process Helper

    /// Synchronously runs an external process and throws if it exits with a non-zero status.
    func runProcess(launchPath: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
            throw ArchiveError.processFailed(
                launchPath: launchPath,
                status: process.terminationStatus,
                message: errMsg
            )
        }
    }

    // MARK: - Errors

    enum ArchiveError: LocalizedError {
        case sourceFolderNotFound(String)
        case processFailed(launchPath: String, status: Int32, message: String)

        var errorDescription: String? {
            switch self {
            case .sourceFolderNotFound(let path):
                return "Source folder not found at \(path)."
            case .processFailed(let path, let status, let message):
                return "\(path) exited with status \(status): \(message)"
            }
        }
    }
}
