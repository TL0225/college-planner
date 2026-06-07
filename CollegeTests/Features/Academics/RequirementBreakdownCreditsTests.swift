// RequirementBreakdownCreditsTests.swift
// Feature: Academics
// Purpose: Academics module — RequirementBreakdownCreditsTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class RequirementBreakdownCreditsTests: XCTestCase {
    func testRequiredCoreUsesListedCoursesNotScraperTitle() {
        let items = [
            AcademicsAuditPanel.AuditItem(
                code: "INFA 702",
                credits: "3",
                title: "Privacy",
                grade: nil,
                planProgress: .notOnPlan,
                isElective: false
            ),
            AcademicsAuditPanel.AuditItem(
                code: "INFA 713",
                credits: "3",
                title: "Risks",
                grade: nil,
                planProgress: .notOnPlan,
                isElective: false
            ),
            AcademicsAuditPanel.AuditItem(
                code: "INFA 735",
                credits: "3",
                title: "Offensive",
                grade: nil,
                planProgress: .notOnPlan,
                isElective: false
            ),
            AcademicsAuditPanel.AuditItem(
                code: "INFA 754",
                credits: "3",
                title: "Monitoring",
                grade: nil,
                planProgress: .notOnPlan,
                isElective: false
            )
        ]
        let category = AcademicsAuditPanel.AuditCategory(
            title: "Required Core (30 Credits)",
            items: items,
            selectCount: 0,
            creditsRequired: 30,
            descriptionCredits: 0
        )
        XCTAssertEqual(RequirementBreakdownCredits.progressTarget(for: category), 12)
    }

    func testSpecializationIncludesProseElectiveCredits() {
        let items = (1...4).map { i in
            AcademicsAuditPanel.AuditItem(
                code: "INFA 72\(i)",
                credits: "3",
                title: "Course \(i)",
                grade: nil,
                planProgress: .notOnPlan,
                isElective: false
            )
        }
        let category = AcademicsAuditPanel.AuditCategory(
            title: "Technical Specialization",
            items: items,
            selectCount: 2,
            creditsRequired: 0,
            descriptionCredits: 6
        )
        XCTAssertEqual(RequirementBreakdownCredits.progressTarget(for: category), 18)
    }

    func testProseOnlyCategoryUsesDescriptionCredits() {
        let category = AcademicsAuditPanel.AuditCategory(
            title: "Choose two 700-800 level courses from INFA, CSC, INFS or BADM prefix (except INFA 701)",
            items: [],
            selectCount: 2,
            creditsRequired: 0,
            descriptionCredits: 6
        )
        XCTAssertEqual(RequirementBreakdownCredits.progressTarget(for: category), 6)
    }

    func testDistributionBucketUsesCatalogCreditsWhenNoListedCourses() {
        let category = AcademicsAuditPanel.AuditCategory(
            title: "General Education Requirements — Foreign Language",
            items: [],
            selectCount: 0,
            creditsRequired: 0,
            catalogCreditsRequired: 16,
            descriptionCredits: 0,
            rowKind: .distributionBucket
        )
        XCTAssertEqual(RequirementBreakdownCredits.progressTarget(for: category), 16)
    }
}
