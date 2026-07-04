// ResumeBuilderFlowTests.swift
// Feature: Resume Tests
// Purpose: Logic-level coverage for Phase 7 E2E flows (save-reopen, entry DnD, apply attach).

import XCTest
@testable import College
import CollegeCareer

@MainActor
final class ResumeBuilderFlowTests: PersistenceTestCase {
    func testSaveToLibraryThenRestoreRoundTrip() async throws {
        let profile = Profile(name: "Flow Student")
        profileContext.insert(profile)
        try profileContext.save()

        let viewModel = ResumeBuilderViewModel(
            snapshot: Self.sampleSnapshot(),
            collegePersistence: CollegePersistence.shared
        )
        viewModel.updateTitle("Flow Round Trip Resume")
        viewModel.setFieldOverride("flow@example.edu", for: .personal(.email))
        viewModel.placeSection(.skills, before: .education)

        let pdf = Data("%PDF-1.4 flow".utf8)
        let saved = try await ResumeBuilderExportService.saveToLibrary(
            pdfData: pdf,
            metadata: viewModel.buildMetadata(),
            displayName: "Flow Round Trip.pdf",
            document: viewModel.document,
            collegePersistence: CollegePersistence.shared
        )
        let savedDoc = try XCTUnwrap(saved)
        viewModel.linkVaultDocument(savedDoc.id)

        let restored = try XCTUnwrap(
            ResumeDocumentRestore.load(
                documentID: savedDoc.id,
                collegePersistence: CollegePersistence.shared
            )
        )
        XCTAssertEqual(restored.title, "Flow Round Trip Resume")
        XCTAssertEqual(restored.fieldOverride(for: .personal(.email)), "flow@example.edu")
        XCTAssertEqual(restored.sectionOrder.first, .summary)
        XCTAssertEqual(restored.sectionOrder[1], .skills)
        XCTAssertEqual(restored.sectionOrder[2], .education)
    }

    func testEntryPlaceReordersExperience() {
        var snapshot = Self.sampleSnapshot()
        let first = ResumeExperienceEntry(
            id: UUID(),
            title: "First Role",
            company: "A",
            location: nil,
            dateRange: "2022 – 2023",
            descriptionText: nil,
            technologies: nil
        )
        let second = ResumeExperienceEntry(
            id: UUID(),
            title: "Second Role",
            company: "B",
            location: nil,
            dateRange: "2023 – Present",
            descriptionText: nil,
            technologies: nil
        )
        snapshot.experiences = [first, second]

        let viewModel = ResumeBuilderViewModel(
            snapshot: snapshot,
            collegePersistence: CollegePersistence.shared
        )
        viewModel.placeEntry(second.id, in: .experience, before: first.id)
        XCTAssertEqual(viewModel.snapshot.experiences.map(\.id), [second.id, first.id])

        viewModel.placeEntry(second.id, in: .experience, before: nil)
        XCTAssertEqual(viewModel.snapshot.experiences.map(\.id), [first.id, second.id])
    }

    func testAttachmentSheetPrefersRecommendedResume() {
        let recommendedID = UUID()
        let otherID = UUID()
        let rows = [
            Self.matchRow(id: otherID, name: "Other.pdf", score: 40, recommended: false),
            Self.matchRow(id: recommendedID, name: "Best.pdf", score: 90, recommended: true),
        ]
        let selected = rows.first(where: \.isRecommended) ?? rows.first
        XCTAssertEqual(selected?.resumeDocumentID, recommendedID)
        XCTAssertEqual(selected?.displayName, "Best.pdf")
    }

    func testApplyPayloadIncludesResumeFileURL() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flow-apply-\(UUID().uuidString).pdf")
        try Data("%PDF-1.4".utf8).write(to: tempURL)

        var payload = ApplyPayloadFactory.goldenContactPayload()
        payload.documents.resumeFileURL = tempURL
        payload.documents.resumeFileName = "Flow.pdf"

        let session = CareerApplySessionStore.shared.open(
            postingURL: URL(string: "https://boards.greenhouse.io/acme/jobs/9")!,
            platform: .greenhouse,
            resumeDocumentID: payload.documents.resumeDocumentID,
            resumeFileName: payload.documents.resumeFileName,
            companyName: "Acme",
            jobTitle: "Engineer",
            payload: payload
        )
        XCTAssertEqual(session.payload?.documents.resumeFileURL, tempURL)
        XCTAssertEqual(session.payload?.documents.resumeFileName, "Flow.pdf")
        CareerApplySessionStore.shared.close(id: session.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path))
    }

    private static func sampleSnapshot() -> ResumeSnapshot {
        ResumeSnapshot(
            snapshotID: UUID(),
            sourceProfileID: UUID(),
            capturedAt: Date(),
            profileRevisionToken: "flow-token",
            personal: ResumePersonalInfo(
                name: "Flow Name",
                pronouns: nil,
                email: "flow@example.com",
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

    private static func matchRow(
        id: UUID,
        name: String,
        score: Int,
        recommended: Bool
    ) -> CareerResumeMatchRow {
        CareerResumeMatchRow(
            resumeDocumentID: id,
            displayName: name,
            overallScore: score,
            keywordScore: score,
            semanticScore: score,
            experienceScore: score,
            matchingSkills: recommended ? ["Swift"] : [],
            missingKeywords: [],
            tip: "",
            isRecommended: recommended
        )
    }
}
