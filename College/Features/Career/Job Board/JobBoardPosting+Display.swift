// JobBoardPosting+Display.swift
// Feature: Career
// Purpose: Career module — JobBoardPosting+Display.
// Data: CollegePersistence / repositories when applicable.

import Foundation

extension JobBoardPosting {
    var normalizedExternalPath: String? {
        let path = externalPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    var displayJobId: String? {
        if let jobIdDisplayText, !jobIdDisplayText.isEmpty { return jobIdDisplayText }
        guard let path = normalizedExternalPath else { return nil }
        if let idx = path.lastIndex(of: "_") {
            let suffix = String(path[path.index(after: idx)...])
            if suffix.hasPrefix("R"), suffix.dropFirst().allSatisfy(\.isNumber) {
                return suffix
            }
        }
        return nil
    }
}
