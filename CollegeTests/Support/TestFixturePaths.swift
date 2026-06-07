// TestFixturePaths.swift
// Feature: Shared
// Purpose: Shared — TestFixturePaths.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Resolves `CollegeTests/Fixtures/*` for tests nested under `Features/`.
enum TestFixturePaths {
    static func courseLeafURL(named filename: String) throws -> URL {
        let bundle = Bundle(for: BundleLocator.self)
        if let url = bundle.url(forResource: filename, withExtension: nil, subdirectory: "Fixtures/CourseLeaf") {
            return url
        }
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = dir
                .appendingPathComponent("Fixtures/CourseLeaf", isDirectory: true)
                .appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            if dir.lastPathComponent == "CollegeTests" { break }
            dir = dir.deletingLastPathComponent()
        }
        throw NSError(
            domain: "TestFixturePaths",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Missing CourseLeaf fixture: \(filename)"]
        )
    }

    static func courseLeafString(named filename: String) throws -> String {
        try String(contentsOf: try courseLeafURL(named: filename), encoding: .utf8)
    }

    static func url(_ relativePath: String) throws -> URL {
        let bundle = Bundle(for: BundleLocator.self)
        let components = relativePath.split(separator: "/").map(String.init)
        guard let filename = components.last else {
            throw NSError(
                domain: "TestFixturePaths",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Invalid fixture path: \(relativePath)"]
            )
        }
        let subdirectory = components.dropLast().joined(separator: "/")
        if let url = bundle.url(
            forResource: filename,
            withExtension: nil,
            subdirectory: subdirectory.isEmpty ? "Fixtures" : "Fixtures/\(subdirectory)"
        ) {
            return url
        }
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = dir
                .appendingPathComponent("Fixtures", isDirectory: true)
                .appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            if dir.lastPathComponent == "CollegeTests" { break }
            dir = dir.deletingLastPathComponent()
        }
        throw NSError(
            domain: "TestFixturePaths",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Missing fixture: \(relativePath)"]
        )
    }
}

private final class BundleLocator: NSObject {}
