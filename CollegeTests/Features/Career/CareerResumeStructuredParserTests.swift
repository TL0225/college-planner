// CareerResumeStructuredParserTests.swift
// Feature: Career / ResumeParsing
// Purpose: Parser coverage for heading/bullet separation and multi-entry sections.

import XCTest
@testable import College

final class CareerResumeStructuredParserTests: XCTestCase {
    func testParsesTimothyStyleExperienceHeadingsAndBullets() {
        let text = """
        Timothy Leung
        Brooklyn, NY | t.leungg04@gmail.com | (631) 693-9443

        WORK EXPERIENCE
        Cybersecurity Analyst Intern - Insmed Incorporated Remote
        Security Governance, Risk, and Compliance (GRC) Focus June 2025 – August 2025
        Authored context-aware security playbooks mapped to SOC 2 Type II and NIST SP 800-53 Rev. 5.
        Executed structured attack-tree exercises to identify critical paths to crown-jewel assets.

        Real Estate Investment Intern — Project Destined — Remote September 2024 – December 2024
        Managed a simulated $500,000 portfolio across multifamily and industrial assets.

        PROJECTS
        Enterprise Infrastructure Defense & GRC Compliance Capstone Fall 2025
        Designed baseline network diagrams and mapped controls to NIST SP 800-53 Rev. 5.
        * VLAN isolation and segmentation reduced lateral movement risk in the lab topology.

        Computer Forensics Investigation Digital Forensics December 2025
        Executed full-lifecycle forensic examinations on Windows and Linux disk images.
        """

        let profile = CareerResumeStructuredParser.parse(plainText: text)

        XCTAssertEqual(profile.experience.count, 2)
        XCTAssertEqual(profile.experience[0].headingLines.count, 2)
        XCTAssertEqual(profile.experience[0].bullets.count, 2)
        XCTAssertTrue(profile.experience[0].bullets.first?.localizedCaseInsensitiveContains("Authored") == true)

        XCTAssertEqual(profile.projects.count, 2)
        XCTAssertTrue(profile.projects[0].headingLines.first?.contains("Capstone") == true)
        XCTAssertEqual(profile.projects[0].bullets.count, 2)
        XCTAssertTrue(profile.projects[1].headingLines.first?.contains("Forensics") == true)
        XCTAssertFalse(profile.projects[1].bullets.isEmpty)
    }

    func testParsedExperienceDisplaySplitsTitleCompanyAndDates() {
        let entry = CareerResumeStructuredProfile.Entry(
            headingLines: [
                "Cybersecurity Analyst Intern - Insmed Incorporated Remote",
                "Security Governance, Risk, and Compliance (GRC) Focus June 2025 – August 2025",
            ],
            bullets: ["Authored context-aware security playbooks."]
        )

        let display = CareerResumeParsedEntryDisplay.experience(from: entry)
        XCTAssertEqual(display.title, "Cybersecurity Analyst Intern")
        XCTAssertEqual(display.organization, "Insmed Incorporated Remote")
        XCTAssertEqual(display.dateLabel, "2025-06 → 2025-08")
        XCTAssertEqual(display.bullets.count, 1)
    }

    func testParsedProjectDisplayKeepsTitleAndBullets() {
        let entry = CareerResumeStructuredProfile.Entry(
            headingLines: ["Enterprise Infrastructure Defense & GRC Compliance Capstone Fall 2025"],
            bullets: [
                "Designed baseline network diagrams.",
                "VLAN isolation and segmentation reduced lateral movement risk.",
            ]
        )

        let display = CareerResumeParsedEntryDisplay.project(from: entry)
        XCTAssertTrue(display.title.contains("Capstone"))
        XCTAssertEqual(display.dateLabel, "2025-10")
        XCTAssertEqual(display.bullets.count, 2)
    }
}
