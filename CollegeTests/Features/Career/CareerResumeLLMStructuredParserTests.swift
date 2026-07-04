// CareerResumeLLMStructuredParserTests.swift
// Feature: Career / ResumeParsing

import XCTest
@testable import College

final class CareerResumeLLMStructuredParserTests: XCTestCase {
    func testProfileFromLLMResponse_groupsExperienceAndProjectBullets() {
        let response = CareerResumeLLMStructuredParser.Response(
            name: "Timothy Leung",
            email: "t.leungg04@gmail.com",
            phone: "(631) 693-9443",
            location: "Brooklyn, NY",
            links: ["https://linkedin.com/in/timothyl0225"],
            summary: nil,
            skills: ["NIST SP 800-53", "SOC 2 Type II"],
            experience: [
                .init(
                    title: "Cybersecurity Analyst Intern",
                    company: "Insmed Incorporated",
                    location: "Remote",
                    subtitle: "Security Governance, Risk, and Compliance (GRC) Focus",
                    startDate: "June 2025",
                    endDate: "August 2025",
                    bullets: [
                        "Authored context-aware security playbooks mapped to SOC 2 Type II.",
                        "Executed structured attack-tree exercises to identify critical paths.",
                    ]
                ),
            ],
            projects: [
                .init(
                    title: "Enterprise Infrastructure Defense & GRC Compliance Capstone",
                    term: "Fall 2025",
                    role: nil,
                    bullets: [
                        "Designed baseline network diagrams and mapped controls to NIST SP 800-53 Rev. 5.",
                        "VLAN isolation and segmentation reduced lateral movement risk.",
                    ]
                ),
                .init(
                    title: "Computer Forensics Investigation",
                    term: "December 2025",
                    role: "Digital Forensics",
                    bullets: ["Executed full-lifecycle forensic examinations on Windows and Linux disk images."]
                ),
            ],
            education: [
                .init(
                    institution: "Dakota State University",
                    degree: "BS Cyber Leadership and Intelligence",
                    major: nil,
                    gpa: "3.8",
                    graduation: "2028",
                    bullets: nil
                ),
            ],
            certifications: nil
        )

        let profile = CareerResumeLLMStructuredParser.profile(from: response)

        XCTAssertEqual(profile.name, "Timothy Leung")
        XCTAssertEqual(profile.experience.count, 1)
        XCTAssertEqual(profile.experience[0].bullets.count, 2)
        XCTAssertTrue(profile.experience[0].headingLines.first?.contains("Insmed") == true)
        XCTAssertTrue(profile.experience[0].headingLines.last?.contains("June 2025") == true)

        XCTAssertEqual(profile.projects.count, 2)
        XCTAssertTrue(profile.projects[0].headingLines.first?.contains("Capstone") == true)
        XCTAssertEqual(profile.projects[0].bullets.count, 2)
        XCTAssertEqual(profile.projects[1].bullets.count, 1)

        XCTAssertEqual(profile.education.count, 1)
        XCTAssertTrue(profile.education[0].headingLines.first?.contains("Dakota State") == true)
        XCTAssertTrue(profile.education[0].bullets.contains { $0.contains("BS Cyber") })
    }

    func testMergePrefersLLMWhenBulletsAreGrouped() {
        let heuristic = CareerResumeStructuredProfile(
            experience: [
                .init(
                    headingLines: [
                        "Cybersecurity Analyst Intern - Insmed Incorporated Remote",
                        "Authored context-aware security playbooks.",
                    ],
                    bullets: []
                ),
            ],
            projects: []
        )

        let llm = CareerResumeLLMStructuredParser.profile(
            from: CareerResumeLLMStructuredParser.Response(
                experience: [
                    .init(
                        title: "Cybersecurity Analyst Intern",
                        company: "Insmed Incorporated",
                        location: "Remote",
                        subtitle: nil,
                        startDate: "June 2025",
                        endDate: "August 2025",
                        bullets: ["Authored context-aware security playbooks."]
                    ),
                ],
                projects: nil,
                education: nil,
                certifications: nil
            )
        )

        let merged = CareerResumeStructuredParsePipeline.merge(heuristic: heuristic, llm: llm)
        XCTAssertEqual(merged.experience.count, 1)
        XCTAssertEqual(merged.experience[0].bullets.count, 1)
        XCTAssertEqual(merged.email, heuristic.email)
    }

    func testPipelineFallsBackToHeuristicWithoutFoundationModels() async {
        let text = """
        WORK EXPERIENCE
        Engineer - Example Corp
        Built APIs and services.
        """
        let profile = await CareerResumeStructuredParsePipeline.parse(plainText: text)
        XCTAssertFalse(profile.experience.isEmpty)
    }
}
