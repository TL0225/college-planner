// TransferManualEntryDraftTests.swift
// Feature: Transfer
// Purpose: Validation + DTO mapping for manual equivalency entry.

import XCTest
@testable import College

final class TransferManualEntryDraftTests: XCTestCase {
    func testValidationRequiresSourceSchool() {
        var draft = TransferManualEntryDraft()
        draft.sourceSchoolName = ""
        draft.sourceCourseCode = "MATH 101"
        draft.targetCourseCode = "MATH 1100"
        XCTAssertEqual(draft.validationError(), "Enter the source school name.")
    }

    func testValidationRequiresTargetSchool() {
        var draft = TransferManualEntryDraft(sourceSchoolName: "Source CC")
        draft.sourceCourseCode = "MATH 101"
        draft.targetCourseCode = "MATH 1100"
        XCTAssertEqual(draft.validationError(), "Enter the target school name.")
    }

    func testMakeDTOTagsManualProvenance() {
        var draft = TransferManualEntryDraft(sourceSchoolName: "Source CC", targetSchoolName: "Target University")
        draft.sourceCourseCode = "ENG 201"
        draft.targetCourseCode = "ENGL 2100"
        draft.sourceCredits = "3"
        draft.targetCredits = "4"
        draft.equivalencyKind = .partial

        let dto = draft.makeDTO(degreeLevel: "undergraduate")
        XCTAssertEqual(dto.sourceKind, .manualEntry)
        XCTAssertEqual(dto.sourceTier, .manual)
        XCTAssertEqual(dto.targetCredits, 4)
        XCTAssertEqual(dto.equivalencyKind, .partial)
        XCTAssertEqual(dto.verificationStatus, .unverified)
        XCTAssertTrue(dto.externalID.hasPrefix("manual-"))
    }

    func testManualEntryResultDetection() {
        let result = TransferCourseResult(
            dedupeKey: "key",
            sourceCourseCode: "MATH 101",
            sourceCredits: 3,
            targetCourseCode: "MATH 1100",
            targetCredits: 3,
            equivalencyKind: .direct,
            verificationStatus: .unverified,
            confidence: 25,
            sourceCount: 1,
            bestTier: .manual,
            hasValidatedProof: false,
            evidence: [
                TransferEvidenceDTO(sourceKind: .manualEntry, sourceTier: .manual, externalID: "manual-1")
            ]
        )
        XCTAssertTrue(result.isManualEntry)
    }
}
