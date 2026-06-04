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
}

private final class BundleLocator: NSObject {}
