// ResumeExportReadiness.swift
// Feature: Resume
// Purpose: Pre-export gates for parser health and manual Typst safeguards.

import Foundation

enum ResumeExportReadiness {
    static let minimumParserHealthPercent = 80

    static func blocksExport(parserHealthPercent: Int?) -> Bool {
        guard let parserHealthPercent else { return false }
        return parserHealthPercent < minimumParserHealthPercent
    }

    static func requiresManualResetConfirmation(
        typstSourceMode: TypstSourceMode,
        manualTypstSource: String?,
        generatedTypstSource: String
    ) -> Bool {
        guard typstSourceMode == .manual else { return false }
        let manual = manualTypstSource?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !manual.isEmpty else { return false }
        return manual != generatedTypstSource.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
