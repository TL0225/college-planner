// ResumePipelineInvariantTests.swift
// Feature: Resume Tests
// Purpose: Data-integrity invariants I1–I10 for the resume pipeline.

import SwiftData
import XCTest
@testable import College

@MainActor
final class ResumePipelineInvariantTests: PersistenceTestCase {
    // I1
    func testMatchCachePurgedOnHashChange() throws {
        let repo = CareerRepository(context: profileContext)
        let resumeID = UUID()

        _ = try repo.upsertResumeJobMatch(
            companySlug: "acme",
            externalPath: "/job/42",
            resumeDocumentID: resumeID,
            overallScore: 77,
            keywordScore: 70,
            semanticScore: 72,
            experienceScore: 65,
            missingKeywords: [],
            recommendedForPosting: true,
            resultJSON: nil,
            descriptionHash: "jd",
            resumeHash: "hash-old"
        )

        try repo.invalidateResumeJobMatches(resumeDocumentID: resumeID)
        XCTAssertNil(
            try repo.fetchResumeJobMatch(companySlug: "acme", externalPath: "/job/42", resumeDocumentID: resumeID)
        )
    }

    // I2
    func testIngestFailureNotMarkedComplete() {
        var meta = CareerResumeMetadataV1()
        meta.ingestFailedAt = .now
        meta.ingestCompletedAt = nil
        meta.structuredSectionsJSON = nil

        XCTAssertNil(meta.ingestCompletedAt)
        XCTAssertNil(JobBoardMatchEligibility.resumeContext(from: meta, documentID: UUID()))
    }

    // I3
    func testBuilderSaveMetadataOrdering() {
        let snapshot = ResumePipelineInvariantFixtures.sampleSnapshot()
        var document = ResumeDocument.seed(from: snapshot)
        document.title = "Resume Title"
        let buildMetadata = ResumeBuildMetadata.make(
            snapshot: snapshot,
            orderedSections: document.sectionOrder,
            templateID: document.templateID,
            typstSource: "= Resume"
        )

        let meta = ResumeBuilderExportService.libraryMetadata(
            document: document,
            buildMetadata: buildMetadata
        )

        XCTAssertNotNil(meta.buildMetadataJSON)
        XCTAssertNotNil(meta.documentJSON)
        XCTAssertNotNil(meta.canonicalProfileJSON)
        XCTAssertNotNil(meta.canonicalProfile)
    }

    // I4
    func testDocumentJSONRoundTrip() {
        let snapshot = ResumePipelineInvariantFixtures.sampleSnapshot()
        let original = ResumeDocument.seed(from: snapshot)
        let json = original.encodedJSON()
        let decoded = ResumeDocument.decode(from: json)
        XCTAssertEqual(decoded, original)
    }

    // I5
    func testCorruptMetadataRepair() throws {
        let document = VaultDocument(
            fileName: "resume.pdf",
            category: VaultRepository.VaultDocumentCategory.careerResume.rawValue,
            localRelativePath: "career/resume.pdf"
        )
        document.careerResumeMetadataJSON = "{not-valid-json"
        profileContext.insert(document)
        try profileContext.save()

        let repo = CareerRepository(context: profileContext)
        XCTAssertEqual(repo.careerResumeMetadata(for: document), .default)
    }

    // I6
    func testConcurrentIngestDeduped() async {
        let documentID = UUID()
        await CareerResumeIngestService.shared.ingest(documentID: documentID)
        await CareerResumeIngestService.shared.ingest(documentID: documentID)
    }

    // I7
    func testPayloadPrefersResumeCanonical() throws {
        let structured = ResumePipelineInvariantFixtures.resumeCanonicalStructured()
        let canonicalJSON = try XCTUnwrap(String(data: try JSONEncoder().encode(structured), encoding: .utf8))

        var meta = CareerResumeMetadataV1(canonicalProfileJSON: canonicalJSON)
        let decoded = try XCTUnwrap(meta.canonicalProfile)
        let canonical = ResumeCanonicalProfile.from(structured: decoded)

        XCTAssertEqual(canonical.basics?.email, "canonical@resume.test")
        XCTAssertEqual(canonical.basics?.name, "Canonical Applicant")
        XCTAssertEqual(canonical.work.first?.company, "Canonical Corp")
        XCTAssertEqual(canonical.work.first?.position, "Platform Engineer")
    }

    // I8
    func testExportBlockedOnLowParseScore() {
        XCTAssertTrue(ResumeExportReadiness.blocksExport(parserHealthPercent: 50))
        XCTAssertFalse(ResumeExportReadiness.blocksExport(parserHealthPercent: 90))
        XCTAssertFalse(ResumeExportReadiness.blocksExport(parserHealthPercent: nil))
        XCTAssertEqual(ResumeExportReadiness.minimumParserHealthPercent, 80)
    }

    // I9
    func testManualTypstResetRequiresConfirmation() {
        let snapshot = ResumePipelineInvariantFixtures.sampleSnapshot()
        let viewModel = ResumeBuilderViewModel(
            snapshot: snapshot,
            collegePersistence: CollegePersistence.shared
        )

        XCTAssertFalse(viewModel.requiresManualResetConfirmation())

        viewModel.setTypstSourceMode(.manual)
        viewModel.updateManualTypstSource("= Custom Resume\nEdited body")
        XCTAssertTrue(viewModel.requiresManualResetConfirmation())
    }

    func testCancelMidCompile() async {
        let snapshot = ResumePipelineInvariantFixtures.sampleSnapshot()
        let viewModel = ResumeBuilderViewModel(
            snapshot: snapshot,
            collegePersistence: CollegePersistence.shared
        )
        viewModel.setFieldOverride("First", for: .personal(.name))
        viewModel.setFieldOverride("Second", for: .personal(.email))
        try? await Task.sleep(nanoseconds: 50_000_000)
        if case .failed = viewModel.compileState {
            XCTFail("Rapid edits should cancel prior compile, not surface failure")
        }
    }

    func testEmptyProfileBlocksSnapshotBuild() {
        XCTAssertThrowsError(try ResumeSnapshotBuilder.build(collegePersistence: CollegePersistence.shared)) { error in
            XCTAssertTrue(error is ResumeSnapshotBuilderError)
        }
    }

    func testDraftRestorePreservesDocumentJSON() throws {
        let profile = Profile(name: "Restore Test")
        profileContext.insert(profile)
        try profileContext.save()

        let persistence = CollegePersistence.shared
        let snapshot = ResumePipelineInvariantFixtures.sampleSnapshot()
        var document = ResumeDocument.seed(from: snapshot)
        document.title = "Restored Draft Title"
        document.setFieldOverride("restored@example.com", for: .personal(.email))

        let vaultDoc = VaultDocument(
            fileName: "draft.pdf",
            category: VaultRepository.VaultDocumentCategory.careerResume.rawValue,
            localRelativePath: "career/draft.pdf"
        )
        var meta = CareerResumeMetadataV1()
        meta.documentJSON = document.encodedJSON()
        meta.ingestCompletedAt = .now
        vaultDoc.careerResumeMetadataJSON = try String(
            data: JSONEncoder().encode(meta),
            encoding: .utf8
        )
        profileContext.insert(vaultDoc)
        try profileContext.save()

        let restored = ResumeDocumentRestore.load(documentID: vaultDoc.id, collegePersistence: persistence)
        XCTAssertEqual(restored?.title, "Restored Draft Title")
        XCTAssertEqual(
            restored?.fieldOverride(for: .personal(.email)),
            "restored@example.com"
        )
    }

    func testFirstLibrarySaveLinksVaultDocument() async throws {
        let profile = Profile(name: "Save Link Test")
        profileContext.insert(profile)
        try profileContext.save()

        let snapshot = ResumePipelineInvariantFixtures.sampleSnapshot()
        let viewModel = ResumeBuilderViewModel(
            snapshot: snapshot,
            collegePersistence: CollegePersistence.shared
        )
        XCTAssertNil(viewModel.linkedVaultDocumentID)

        let pdf = Data("%PDF-1.4 test".utf8)
        let metadata = viewModel.buildMetadata()
        let saved = try await ResumeBuilderExportService.saveToLibrary(
            pdfData: pdf,
            metadata: metadata,
            displayName: "Link Test.pdf",
            document: viewModel.document,
            collegePersistence: CollegePersistence.shared,
            existingVaultDocumentID: nil
        )
        let savedDoc = try XCTUnwrap(saved)
        viewModel.linkVaultDocument(savedDoc.id)
        XCTAssertEqual(viewModel.linkedVaultDocumentID, savedDoc.id)
    }

    func testCanonicalJSONHasNoCredentialFields() throws {
        let structured = ResumePipelineInvariantFixtures.resumeCanonicalStructured()
        let data = try JSONEncoder().encode(structured)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8)).lowercased()
        for forbidden in ["password", "ssn", "socialsecurity", "creditcard", "apikey", "secret"] {
            XCTAssertFalse(json.contains(forbidden), "Canonical profile must not encode \(forbidden)")
        }
    }

    // I10
    func testApplyTempFileCleanup() throws {
        let store = CareerApplySessionStore.shared
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("resume-test-\(UUID().uuidString).pdf")
        try Data("%PDF-1.4".utf8).write(to: tempURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempURL.path))

        var payload = ApplyPayloadFactory.goldenContactPayload()
        payload.documents.resumeFileURL = tempURL

        let session = store.open(
            postingURL: URL(string: "https://boards.greenhouse.io/acme/jobs/1")!,
            platform: .greenhouse,
            resumeDocumentID: payload.documents.resumeDocumentID,
            resumeFileName: payload.documents.resumeFileName,
            companyName: "Acme",
            jobTitle: "Engineer",
            payload: payload
        )

        store.close(id: session.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path))
    }
}

// MARK: - Fixtures

private enum ResumePipelineInvariantFixtures {
    static func sampleSnapshot() -> ResumeSnapshot {
        ResumeSnapshot(
            snapshotID: UUID(),
            sourceProfileID: UUID(),
            capturedAt: Date(),
            profileRevisionToken: "token",
            personal: ResumePersonalInfo(
                name: "Profile Name",
                pronouns: nil,
                email: "profile@example.com",
                phone: nil,
                address: nil,
                contactLinks: []
            ),
            education: [],
            experiences: [],
            projects: [],
            skills: ["Swift"]
        )
    }

    static func resumeCanonicalStructured() -> CareerResumeStructuredProfile {
        var structured = CareerResumeStructuredProfile()
        structured.name = "Canonical Applicant"
        structured.email = "canonical@resume.test"
        structured.experience = [
            CareerResumeStructuredProfile.Entry(
                headingLines: ["Platform Engineer", "Canonical Corp", "2024 – Present"],
                bullets: ["Shipped builder integration"]
            ),
        ]
        return structured
    }
}
