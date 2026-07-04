// CareerResumeEditSession.swift
// Feature: Career
// Purpose: In-memory accept/reject/edit state for resume tailoring.

import Foundation
import Observation
import CollegeCareer

@Observable
@MainActor
final class CareerResumeEditSession {
    enum SuggestionDecision: Equatable {
        case accepted
        case rejected
        case edited(String)
    }

    let sourceDocumentID: UUID
    let jobTitle: String
    let companyName: String
    let platform: JobBoardPlatform
    var baseProfile: CareerResumeStructuredProfile
    var suggestions: [CareerResumeSuggestion]
    var decisions: [UUID: SuggestionDecision] = [:]
    var isGenerating: Bool = false
    var liveMatchScoreBefore: Int
    var liveMatchScoreAfter: Int

    init(
        sourceDocumentID: UUID,
        jobTitle: String,
        companyName: String,
        platform: JobBoardPlatform,
        baseProfile: CareerResumeStructuredProfile,
        suggestions: [CareerResumeSuggestion] = [],
        liveMatchScoreBefore: Int = 0
    ) {
        self.sourceDocumentID = sourceDocumentID
        self.jobTitle = jobTitle
        self.companyName = companyName
        self.platform = platform
        self.baseProfile = baseProfile
        self.suggestions = suggestions
        self.liveMatchScoreBefore = liveMatchScoreBefore
        self.liveMatchScoreAfter = liveMatchScoreBefore
    }

    func acceptedText(for suggestion: CareerResumeSuggestion) -> String {
        switch decisions[suggestion.id] {
        case .accepted:
            return suggestion.proposedBullet.isEmpty ? suggestion.originalBullet : suggestion.proposedBullet
        case .edited(let text):
            return text
        case .rejected, .none:
            return suggestion.originalBullet
        }
    }

    func isAccepted(_ suggestion: CareerResumeSuggestion) -> Bool {
        switch decisions[suggestion.id] {
        case .accepted, .edited: return true
        default: return false
        }
    }

    func applyAllSafe() {
        for suggestion in suggestions where suggestion.tier == .safe && suggestion.type != .metricPrompt {
            guard decisions[suggestion.id] == nil else { continue }
            guard !suggestion.proposedBullet.isEmpty else { continue }
            decisions[suggestion.id] = .accepted
        }
        refreshLiveScore()
    }

    func undo(decisionFor id: UUID) {
        decisions.removeValue(forKey: id)
        refreshLiveScore()
    }

    func exportProfile() -> CareerResumeStructuredProfile {
        var profile = baseProfile
        var experience = profile.experience
        for idx in experience.indices {
            var bullets = experience[idx].bullets
            for bulletIdx in bullets.indices {
                let original = bullets[bulletIdx]
                if let suggestion = suggestions.first(where: { $0.originalBullet == original }),
                   isAccepted(suggestion) {
                    let replacement = acceptedText(for: suggestion)
                    if !replacement.isEmpty, replacement != original {
                        bullets[bulletIdx] = replacement
                    }
                }
            }
            experience[idx] = CareerResumeStructuredProfile.Entry(
                headingLines: experience[idx].headingLines,
                bullets: bullets
            )
        }
        profile.experience = experience
        return profile
    }

    func previewText() -> String {
        CareerResumeProfileTextAssembler.assemble(exportProfile())
    }

    func refreshLiveScore() {
        let acceptedCount = suggestions.filter(isAccepted).count
        let estimated = suggestions.compactMap(\.scoreDeltaEstimate).reduce(0, +)
        let appliedEstimate = suggestions.filter(isAccepted).compactMap(\.scoreDeltaEstimate).reduce(0, +)
        let bonus = acceptedCount > 0 ? appliedEstimate : 0
        liveMatchScoreAfter = min(100, liveMatchScoreBefore + bonus)
        _ = estimated
    }

    func saveTailoredCopy(using persistence: CollegePersistence) async throws -> VaultDocument? {
        let text = previewText()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let source = try persistence.vaultRepository.fetchDocument(id: sourceDocumentID) else { return nil }

        let pdfData = CareerResumePDFExporter.renderSingleColumnPDF(text: text)
        let exportName = (source.customDisplayName ?? source.fileName)
            .replacingOccurrences(of: ".pdf", with: "", options: .caseInsensitive)
            + "_Tailored.pdf"

        let exportURL = FileManager.default.temporaryDirectory.appendingPathComponent(exportName)
        try pdfData.write(to: exportURL)
        defer { try? FileManager.default.removeItem(at: exportURL) }

        let profile = exportProfile()
        let structuredJSON: String? = {
            guard let data = try? JSONEncoder().encode(profile),
                  let json = String(data: data, encoding: .utf8) else { return nil }
            return json
        }()
        let textHash = CareerResumeHashing.hash(
            normalizedPlainText: CareerResumeHashing.normalize(text)
        )

        var initialMeta = CareerResumeMetadataV1()
        initialMeta.kind = .tailored
        initialMeta.targetRole = jobTitle
        initialMeta.platformTarget = platform.rawValue
        initialMeta.structuredSectionsJSON = structuredJSON
        initialMeta.canonicalProfileJSON = structuredJSON
        initialMeta.parsedTextHash = textHash
        initialMeta.ingestCompletedAt = structuredJSON != nil ? .now : nil
        initialMeta.parserHealthPercent = 85

        guard let exported = try await persistence.importCareerResume(
            from: exportURL,
            initialMetadata: initialMeta
        ) else { return nil }

        exported.versionOf = source.id
        try persistence.setCareerResumeMetadata(initialMeta, for: exported)
        persistence.save()
        await VaultDocumentTextIndexer.shared.schedule(documentID: exported.id)
        return exported
    }

    /// Saves accepted tailoring as a builder draft (`documentJSON`) linked to the source resume.
    func createBuilderDraft(using persistence: CollegePersistence) async throws -> VaultDocument? {
        let profile = exportProfile()
        let canonical = ResumeCanonicalProfile.from(structured: profile)
        guard canonical.hasContent else { return nil }

        guard let snapshot = try? ResumeSnapshotBuilder.build(collegePersistence: persistence) else { return nil }
        var document = ResumeDocument.seed(from: snapshot)
        document.title = "\(jobTitle) — \(companyName)"
        document = applyTailoringOverrides(to: document, profile: profile)

        let buildMeta = ResumeBuildMetadata.make(
            snapshot: ResumeDocumentCompiler.mergedSnapshot(from: document),
            orderedSections: document.sectionOrder,
            templateID: document.templateID,
            typstSource: ""
        )

        var initialMeta = ResumeBuilderExportService.libraryMetadata(document: document, buildMetadata: buildMeta)
        initialMeta.kind = .tailored
        initialMeta.targetRole = jobTitle
        initialMeta.platformTarget = platform.rawValue
        initialMeta.derivedFromDocumentID = sourceDocumentID

        let pdfData = CareerResumePDFExporter.renderSingleColumnPDF(text: previewText())
        let exportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TailoredDraft-\(UUID().uuidString).pdf")
        try pdfData.write(to: exportURL)
        defer { try? FileManager.default.removeItem(at: exportURL) }

        guard let exported = try await persistence.importCareerResume(
            from: exportURL,
            initialMetadata: initialMeta
        ) else { return nil }

        try persistence.setCareerResumeMetadata(initialMeta, for: exported)
        persistence.bumpCareerRevision()
        return exported
    }

    private func applyTailoringOverrides(
        to document: ResumeDocument,
        profile: CareerResumeStructuredProfile
    ) -> ResumeDocument {
        var document = document
        for (expIndex, entry) in profile.experience.enumerated() {
            for (bulletIndex, bullet) in entry.bullets.enumerated() {
                let key = "experience.\(expIndex).bullet.\(bulletIndex)"
                document.fieldOverrides[key] = bullet
            }
            if let heading = entry.headingLines.first {
                document.fieldOverrides["experience.\(expIndex).heading"] = heading
            }
        }
        document.touch()
        return document
    }
}
