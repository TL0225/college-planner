// CareerResumeParseSanitizerTests.swift
// Feature: Career / ResumeParsing

import XCTest
@testable import College

final class CareerResumeParseSanitizerTests: XCTestCase {
    private var resumeText: String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Resume/TimothyLeungResumeExtract.txt")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func testNormalizer_joinsWrappedSOC2AndRemovesOrphanBullets() {
        let normalized = CareerResumePlainTextNormalizer.normalize(resumeText)
        XCTAssertTrue(normalized.contains("SOC 2 Type II"))
        XCTAssertFalse(normalized.contains("\n●\n"))
    }

    func testNormalizer_keepsSecondUniversitySeparateFromCoursework() {
        let text = """
        EDUCATION
        University at Buffalo - The State of New York
        Coursework: Systems Security, Digital Forensics
        Dakota State University
        Graduated: May 2028
        """
        let normalized = CareerResumePlainTextNormalizer.normalize(text)
        XCTAssertTrue(normalized.contains("\nDakota State University\n"))
        XCTAssertFalse(normalized.contains("Coursework: Systems Security, Digital Forensics Dakota State University"))
    }

    func testHeuristicParser_splitsThreeExperienceRoles() {
        let normalized = CareerResumePlainTextNormalizer.normalize(resumeText)
        let profile = CareerResumeStructuredParser.parse(plainText: normalized)
        let sanitized = CareerResumeParseSanitizer.sanitize(profile, sourceText: normalized)

        XCTAssertFalse(resumeText.isEmpty, "Fixture failed to load")
        XCTAssertGreaterThanOrEqual(sanitized.experience.count, 3)
        XCTAssertTrue(sanitized.experience.contains {
            $0.headingLines.joined(separator: " ").localizedCaseInsensitiveContains("Real Estate Investment Intern")
        })
        XCTAssertFalse(sanitized.experience[0].bullets.contains {
            $0.localizedCaseInsensitiveContains("Real Estate Investment Intern")
        })
    }

    func testSanitizer_dropsHallucinatedCISSP() {
        var profile = CareerResumeStructuredProfile(
            certifications: ["Certified Information Systems Security Professional (CISSP)"]
        )
        profile = CareerResumeParseSanitizer.sanitize(profile, sourceText: resumeText)
        XCTAssertTrue(profile.certifications.isEmpty)
    }

    func testSanitizer_mergesSplitProjectBullets() {
        let bullets = [
            "Architected a segmented virtual network using pfSense and Proxmox with strict ”default deny",
            "” VLAN isolation, aligning a multi-tier web stack directly with CIS Critical Security Controls and NIST compliance baselines.",
        ]
        let merged = CareerResumeParseSanitizer.mergeFragmentedBullets(bullets)
        XCTAssertEqual(merged.count, 1)
        XCTAssertTrue(merged[0].contains("VLAN isolation"))
    }

    func testSanitizer_promotesMisplacedExperienceHeadingFromBullets() {
        let entry = CareerResumeStructuredProfile.Entry(
            headingLines: [
                "Cybersecurity Analyst Intern - Insmed Incorporated Remote",
                "Security Governance, Risk, and Compliance (GRC) Focus June 2025 - August 2025",
            ],
            bullets: [
                "Assessed the information security risk posture of 60+ third-party vendors.",
                "Real Estate Investment Intern - Project Destined Remote",
                "Should not stay in previous role.",
            ]
        )
        let repaired = CareerResumeParseSanitizer.sanitize(
            CareerResumeStructuredProfile(experience: [entry]),
            sourceText: resumeText
        )
        XCTAssertEqual(repaired.experience.count, 2)
        XCTAssertEqual(repaired.experience[0].bullets.count, 1)
        XCTAssertTrue(repaired.experience[1].headingLines.first?.contains("Real Estate") == true)
    }
}
