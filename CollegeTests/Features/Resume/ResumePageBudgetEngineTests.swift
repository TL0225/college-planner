// ResumePageBudgetEngineTests.swift
// Feature: Resume
// Purpose: Page budget and platform adaptation regression tests.

import Foundation
import Testing
@testable import College

@Suite("ResumePageBudgetEngineTests")
struct ResumePageBudgetEngineTests {
    private func sampleProfile() -> ResumeCanonicalProfile {
        ResumeCanonicalProfile(
            basics: .init(
                name: "Alex Example",
                email: nil,
                phone: nil,
                location: nil,
                summary: String(repeating: "Experienced engineer building reliable systems. ", count: 12),
                links: []
            ),
            work: (0..<6).map { index in
                ResumeCanonicalProfile.WorkEntry(
                    id: UUID(),
                    position: "Engineer \(index)",
                    company: "Company \(index)",
                    highlights: ["Delivered feature \(index)", "Improved reliability \(index)"]
                )
            },
            education: [
                ResumeCanonicalProfile.EducationEntry(
                    id: UUID(),
                    institution: "State University",
                    studyType: "BS",
                    area: "Computer Science"
                )
            ],
            projects: [
                ResumeCanonicalProfile.ProjectEntry(
                    id: UUID(),
                    name: "Capstone",
                    highlights: ["Built distributed service"]
                )
            ],
            skills: ["Swift", "Python", "AWS"],
            certifications: ["AWS Certified"]
        )
    }

    @Test("Oracle adaptation applies compression when over page budget")
    func oracleAdaptationCompressesWhenNeeded() {
        let profile = sampleProfile()
        let baseline = ResumePageBudgetEngine.estimatePageCount(for: profile)
        let result = ResumePageBudgetEngine.adaptWithBudget(
            profile: profile,
            platform: JobBoardPlatform.oracle,
            baselinePageCount: 1
        )

        #expect(result.baselinePageCount == 1)
        #expect(!result.portalTips.isEmpty)
        #expect(result.adaptedProfile.projects.isEmpty || result.compressionStepsApplied.contains(.stripOptionalSections))
    }

    @Test("Greenhouse adaptation preserves structure")
    func greenhouseAdaptationIsMostlyContentOnly() {
        let profile = sampleProfile()
        let adapted = profile.adapted(for: JobBoardPlatform.greenhouse)
        #expect(adapted.work.count == profile.work.count)
        #expect(adapted.education.count == profile.education.count)
    }

    @Test("Workday adaptation inlines skills into experience")
    func workdayAdaptationInlinesSkills() {
        let profile = ResumeCanonicalProfile(
            work: [
                ResumeCanonicalProfile.WorkEntry(
                    id: UUID(),
                    position: "Engineer",
                    company: "Acme",
                    highlights: ["Shipped APIs"]
                )
            ],
            skills: ["Swift", "PostgreSQL"]
        )
        let adapted = profile.adapted(for: JobBoardPlatform.workday)
        #expect(adapted.work.first?.highlights.contains(where: { $0.localizedCaseInsensitiveContains("Swift") }) == true)
    }
}
