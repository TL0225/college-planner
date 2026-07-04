// TransferManualEntryDraft.swift
// Feature: Transfer
// Purpose: Form state + validation for user-entered transfer equivalencies.

import Foundation

/// In-progress manual equivalency the user types in the Transfer Database sheet.
struct TransferManualEntryDraft: Equatable {
    var sourceSchoolName: String
    var targetSchoolName: String
    var sourceCourseCode: String
    var sourceCourseTitle: String
    var sourceCredits: String
    var targetCourseCode: String
    var targetCourseTitle: String
    var targetCredits: String
    var equivalencyKind: TransferEquivalencyKind
    var effectiveTerm: String
    var sourceURL: String

    init(sourceSchoolName: String = "", targetSchoolName: String = "") {
        self.sourceSchoolName = sourceSchoolName
        self.targetSchoolName = targetSchoolName
        self.sourceCourseCode = ""
        self.sourceCourseTitle = ""
        self.sourceCredits = "3"
        self.targetCourseCode = ""
        self.targetCourseTitle = ""
        self.targetCredits = "3"
        self.equivalencyKind = .direct
        self.effectiveTerm = ""
        self.sourceURL = ""
    }

    func validationError() -> String? {
        let sourceName = sourceSchoolName.trimmingCharacters(in: .whitespacesAndNewlines)
        if sourceName.isEmpty {
            return "Enter the source school name."
        }
        let targetName = targetSchoolName.trimmingCharacters(in: .whitespacesAndNewlines)
        if targetName.isEmpty {
            return "Enter the target school name."
        }
        let sourceCode = sourceCourseCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetCode = targetCourseCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if sourceCode.isEmpty {
            return "Enter the source course code."
        }
        if targetCode.isEmpty {
            return "Enter the target course code."
        }
        guard parsedCredits(sourceCredits) != nil else {
            return "Source credits must be a whole number greater than zero."
        }
        guard parsedCredits(targetCredits) != nil else {
            return "Target credits must be a whole number greater than zero."
        }
        let url = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.isEmpty, URL(string: url)?.scheme == nil {
            return "Source URL must be a valid http or https link."
        }
        return nil
    }

    func makeDTO(degreeLevel: String) -> TransferEquivalencyDTO {
        let sourceName = sourceSchoolName.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceManifestID = TransferNormalization.normalizeSchoolID(sourceName)
        let targetName = targetSchoolName.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetManifestID = TransferNormalization.normalizeSchoolID(targetName)
        let sourceCreditsValue = parsedCredits(sourceCredits) ?? 3
        let targetCreditsValue = parsedCredits(targetCredits) ?? 3
        let externalID = "manual-\(UUID().uuidString)"

        return TransferEquivalencyDTO(
            sourceSchoolID: sourceManifestID,
            sourceSchoolName: sourceName,
            sourceCourseCode: sourceCourseCode.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceCourseTitle: trimmedOptional(sourceCourseTitle),
            sourceCredits: sourceCreditsValue,
            targetSchoolID: targetManifestID,
            targetSchoolName: targetName,
            targetCourseCode: targetCourseCode.trimmingCharacters(in: .whitespacesAndNewlines),
            targetCourseTitle: trimmedOptional(targetCourseTitle),
            targetCredits: targetCreditsValue,
            equivalencyKind: equivalencyKind,
            degreeLevel: TransferNormalization.normalizeDegreeLevel(degreeLevel),
            sourceTier: .manual,
            sourceKind: .manualEntry,
            externalID: externalID,
            sourceURL: trimmedOptional(sourceURL),
            effectiveTerm: trimmedOptional(effectiveTerm),
            verificationStatus: .unverified,
            notes: nil
        )
    }

    private func parsedCredits(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), value > 0, value <= 32 else { return nil }
        return value
    }

    private func trimmedOptional(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension TransferCourseResult {
    var isManualEntry: Bool {
        bestTier == .manual || evidence.contains { $0.sourceKind == .manualEntry }
    }

    var primarySourceLabel: String {
        evidence.first?.sourceKind.displayName ?? bestTier.displayName
    }
}

extension TransferSourceTier {
    var displayName: String {
        switch self {
        case .official: return "Official"
        case .communityVerified: return "Community Verified"
        case .community: return "Community"
        case .manual: return "Manual Entry"
        }
    }
}
