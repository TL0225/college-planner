// RequirementProgressEngineTests.swift
// Feature: Academics
// Purpose: Academics module — RequirementProgressEngineTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class RequirementProgressEngineTests: XCTestCase {
    func testChooseOneBothCompletedCapsAtHeaderCredits() {
        let section = RequirementSectionSnapshot(
            categoryKey: "Math — Select one",
            requirementKind: .chooseOne,
            selectCount: 1,
            creditsRequired: 4,
            descriptionCredits: 4,
            requiredItems: [],
            electiveItems: [
                RequirementCourseSnapshot(code: "MATH-UA 121", credits: 4, isCompleted: true, isElective: true),
                RequirementCourseSnapshot(code: "MATH-UA 131", credits: 4, isCompleted: true, isElective: true),
            ],
            assignedItems: []
        )
        XCTAssertEqual(RequirementProgressEngine.target(for: section), 4)
        XCTAssertEqual(RequirementProgressEngine.completed(for: section), 4)
        XCTAssertTrue(RequirementProgressEngine.isDone(for: section))
    }

    func testDistributionBucketCapsAssignedCredits() {
        let section = RequirementSectionSnapshot(
            categoryKey: "Gen Ed — Foreign Language",
            requirementKind: .distributionBucket,
            selectCount: 0,
            creditsRequired: 16,
            descriptionCredits: 16,
            requiredItems: [],
            electiveItems: [],
            assignedItems: [
                RequirementCourseSnapshot(code: "SPAN-UA 1", credits: 8, isCompleted: true, isElective: true),
                RequirementCourseSnapshot(code: "SPAN-UA 2", credits: 8, isCompleted: true, isElective: true),
                RequirementCourseSnapshot(code: "SPAN-UA 3", credits: 4, isCompleted: true, isElective: true),
            ]
        )
        XCTAssertEqual(RequirementProgressEngine.completed(for: section), 16)
    }
}

final class RequirementBreakdownCreditsChooseOneTests: XCTestCase {
    func testSumCompletedCreditsUsesTopNForChooseOne() {
        let items = [
            AcademicsAuditPanel.AuditItem(
                code: "A", credits: "4", title: "", grade: nil, planProgress: .completed, isElective: true
            ),
            AcademicsAuditPanel.AuditItem(
                code: "B", credits: "4", title: "", grade: nil, planProgress: .completed, isElective: true
            ),
        ]
        let completed = RequirementBreakdownCredits.sumCompletedCredits(
            items: items,
            selectCount: 1,
            descriptionCredits: 4,
            headerCredits: 4
        )
        XCTAssertEqual(completed, 4)
    }
}
