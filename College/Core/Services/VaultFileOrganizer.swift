// VaultFileOrganizer.swift
// Feature: Core
// Purpose: Core module — for.
// Data: CollegePersistence / repositories when applicable.

import Foundation
import AppKit

// MARK: - VaultFileOrganizer

/// Namespace enum for organizing classified vault documents into structured
/// ~/Documents/College/{semester}/{courseCode}/{type}/ directories with
/// macOS Finder tags and a 60-second undo buffer.
enum VaultFileOrganizer {

    // MARK: - Undo Buffer

    nonisolated(unsafe) private static var undoBuffer: [(src: URL, dst: URL, expires: Date)] = []

    // MARK: - Public API

    /// Moves `fileURL` into the semester/course/type folder hierarchy, applies
    /// Finder tags, records an undo entry, and returns the destination URL.
    static func organize(
        fileURL: URL,
        result: DocumentClassifierService.ClassificationResult
    ) async throws -> URL {
        let semester   = currentSemesterLabel()
        let courseCode = result.courseCode ?? "General"
        let typeName   = result.documentType.rawValue.capitalized

        // 1. Build target folder
        let baseURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/College", isDirectory: true)
            .appendingPathComponent(semester, isDirectory: true)
            .appendingPathComponent(courseCode, isDirectory: true)
            .appendingPathComponent(typeName, isDirectory: true)

        // 2. Create folder if needed
        try FileManager.default.createDirectory(
            at: baseURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // 3. Build destination filename
        let shortFmt = ISO8601DateFormatter()
        shortFmt.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        let dateString = shortFmt.string(from: Date())
        let ext        = fileURL.pathExtension.isEmpty ? "pdf" : fileURL.pathExtension
        let prefix     = result.courseCode ?? "DOC"
        let typePart   = result.documentType.rawValue
        let filename   = "\(prefix)_\(typePart)_\(dateString).\(ext)"
        let destination = baseURL.appendingPathComponent(filename)

        // 4. Move file
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: fileURL, to: destination)

        // 5. Apply Finder tags
        var tags: [String] = [result.documentType.rawValue, semester]
        if let code = result.courseCode { tags.insert(code, at: 0) }
        setFinderTags(tags, forURL: destination)

        // 6. Record undo entry (expires after 60 seconds)
        let entry = (src: fileURL, dst: destination, expires: Date().addingTimeInterval(60))
        undoBuffer.append(entry)
        processUndoBuffer()

        return destination
    }

    // MARK: - Finder Tags

    /// Applies macOS Finder colour tags to the file at `url`.
    static func setFinderTags(_ tags: [String], forURL url: URL) {
        try? (url as NSURL).setResourceValue(tags as NSArray, forKey: URLResourceKey.tagNamesKey)
    }

    // MARK: - Semester Label

    /// Returns the current semester label stored in UserDefaults,
    /// falling back to "Current Semester".
    static func currentSemesterLabel() -> String {
        UserDefaults.standard.string(forKey: "currentSemesterLabel") ?? "Current Semester"
    }

    // MARK: - Weekly Folders

    /// Creates ~/Documents/College/{semester}/{course}/Week{n}/ subdirectories
    /// for each week number supplied.
    static func createWeeklyFolders(for weekNumbers: [Int], course: String, semester: String) {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/College", isDirectory: true)
            .appendingPathComponent(semester, isDirectory: true)
            .appendingPathComponent(course, isDirectory: true)

        for week in weekNumbers {
            let weekFolder = base.appendingPathComponent("Week\(week)", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: weekFolder,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
    }

    // MARK: - Undo

    /// Removes all undo buffer entries whose expiry has passed.
    static func processUndoBuffer() {
        let now = Date()
        undoBuffer.removeAll { $0.expires < now }
    }

    /// Moves the most recently organised file back to its original location,
    /// provided the 60-second undo window has not expired.
    static func undoLastOrganization() throws {
        processUndoBuffer()

        guard let last = undoBuffer.last else {
            throw VaultFileOrganizerError.noUndoAvailable
        }

        // Recreate source directory if it was removed
        let srcDir = last.src.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: srcDir,
            withIntermediateDirectories: true,
            attributes: nil
        )

        if FileManager.default.fileExists(atPath: last.src.path) {
            try FileManager.default.removeItem(at: last.src)
        }
        try FileManager.default.moveItem(at: last.dst, to: last.src)

        undoBuffer.removeLast()
    }
}

// MARK: - VaultFileOrganizerError

enum VaultFileOrganizerError: LocalizedError {
    case noUndoAvailable

    var errorDescription: String? {
        switch self {
        case .noUndoAvailable:
            return "No recent organization action is available to undo (60-second window expired)."
        }
    }
}
