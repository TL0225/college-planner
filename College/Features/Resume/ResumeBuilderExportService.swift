// ResumeBuilderExportService.swift
// Feature: Resume
// Purpose: Save builder output to the resume library or export via NSSavePanel.

import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum ResumeBuilderExportService {
    static func saveToLibrary(
        pdfData: Data,
        metadata: ResumeBuildMetadata,
        displayName: String,
        document: ResumeDocument,
        collegePersistence: CollegePersistence,
        existingVaultDocumentID: UUID? = nil
    ) async throws -> VaultDocument? {
        let fileName = sanitizedFileName(displayName)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)

        try pdfData.write(to: tempURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let initialMeta = libraryMetadata(document: document, buildMetadata: metadata)

        if let existingVaultDocumentID,
           let existing = try? collegePersistence.vaultRepository.fetchDocument(id: existingVaultDocumentID) {
            try await collegePersistence.vaultRepository.replaceVaultDocumentContent(
                documentID: existingVaultDocumentID,
                fromSelectedURL: tempURL
            )
            try collegePersistence.setCareerResumeMetadata(initialMeta, for: existing)
            collegePersistence.fetchVaultDocuments()
            collegePersistence.bumpVaultRevision()
            collegePersistence.scheduleCareerResumeIngest(documentID: existingVaultDocumentID)
            return existing
        }

        guard let document = try await collegePersistence.importCareerResume(
            from: tempURL,
            initialMetadata: initialMeta
        ) else {
            return nil
        }
        return document
    }

    static func libraryMetadata(
        document: ResumeDocument,
        buildMetadata: ResumeBuildMetadata
    ) -> CareerResumeMetadataV1 {
        let snapshot = ResumeDocumentCompiler.mergedSnapshot(from: document)
        let canonical = ResumeCanonicalProfile.from(snapshot: snapshot)
        let structured = canonical.toStructuredProfile()

        var initialMeta = CareerResumeMetadataV1()
        initialMeta.kind = .general
        initialMeta.buildMetadataJSON = buildMetadata.encodedJSON()
        initialMeta.documentJSON = document.encodedJSON()
        if structured.hasContent,
           let data = try? JSONEncoder().encode(structured),
           let json = String(data: data, encoding: .utf8) {
            initialMeta.canonicalProfileJSON = json
            initialMeta.parsedTextHash = CareerResumeHashing.hash(normalizedPlainText: json)
        }
        return initialMeta
    }

    static func exportToUserChosenDestination(
        pdfData: Data,
        defaultFileName: String
    ) -> Bool {
        let panel = NSSavePanel()
        panel.title = "Export Resume PDF"
        panel.nameFieldStringValue = defaultFileName
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return false }

        do {
            try pdfData.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func exportDOCXToUserChosenDestination(
        docxData: Data,
        defaultFileName: String
    ) -> Bool {
        let panel = NSSavePanel()
        panel.title = "Export Resume Word Document"
        panel.nameFieldStringValue = defaultFileName.replacingOccurrences(of: ".pdf", with: ".docx")
        panel.allowedContentTypes = [UTType(filenameExtension: "docx") ?? .data]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return false }

        do {
            try docxData.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static func sanitizedFileName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Resume" : trimmed
        let safe = base.replacingOccurrences(
            of: #"[^A-Za-z0-9._ -]"#,
            with: "_",
            options: .regularExpression
        )
        return safe.lowercased().hasSuffix(".pdf") ? safe : "\(safe).pdf"
    }
}
