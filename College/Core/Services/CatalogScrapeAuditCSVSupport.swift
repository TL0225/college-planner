// CatalogScrapeAuditCSVSupport.swift
// Feature: Core
// Purpose: Core module — CatalogScrapeAuditCSVSupport.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Writes optional scrape audit CSVs for ModernCampus course imports.
enum CatalogScrapeAuditCSVSupport {
    static func resolveExportDirectories(sourceFilePath: String = #filePath) throws -> [URL] {
        let sourceURL = URL(fileURLWithPath: sourceFilePath)
        let repoRoot = sourceURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let repoExports = repoRoot.appendingPathComponent("exports", isDirectory: true)

        let userHomeAppSupportExports = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("College", isDirectory: true)
            .appendingPathComponent("exports", isDirectory: true)

        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appSupportExports = appSupport
            .appendingPathComponent("College", isDirectory: true)
            .appendingPathComponent("exports", isDirectory: true)

        return [repoExports, userHomeAppSupportExports, appSupportExports]
    }

    static func writeAuditFile(
        manifest: SchoolManifest,
        rows: [(catoid: String, title: String, course: CatalogCourse)],
        sourceFilePath: String = #filePath
    ) throws -> URL {
        let timestamp = Int(Date().timeIntervalSince1970)
        let safeSchoolID = manifest.id
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9_-]+", with: "_", options: .regularExpression)
        let filename = "\(safeSchoolID)_onboarding_scrape_\(timestamp).csv"

        func csvCell(_ value: String) -> String {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }

        var lines: [String] = []
        lines.append("school_id,school_name,catalog_catoid,catalog_title,course_code,course_title,credits,department,description")

        for row in rows {
            let course = row.course
            let line = [
                csvCell(manifest.id),
                csvCell(manifest.name),
                csvCell(row.catoid),
                csvCell(row.title),
                csvCell(course.courseCode),
                csvCell(course.title),
                String(course.credits),
                csvCell(course.department ?? ""),
                csvCell(course.description ?? "")
            ].joined(separator: ",")
            lines.append(line)
        }

        let content = lines.joined(separator: "\n")
        let candidateDirectories = try resolveExportDirectories(sourceFilePath: sourceFilePath)
        var lastError: Error?

        for directory in candidateDirectories {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let fileURL = directory.appendingPathComponent(filename)
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                return fileURL
            } catch {
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }

        throw CocoaError(.fileWriteUnknown)
    }
}
