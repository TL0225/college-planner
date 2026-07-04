// CareerResumeSectionSegmenterTests.swift
// Feature: Career / ResumeParsing

import XCTest
@testable import College

final class CareerResumeSectionSegmenterTests: XCTestCase {
    private var resumeText: String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Resume/TimothyLeungResumeExtract.txt")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func testSegmenter_splitsTimothyResumeSections() {
        let normalized = CareerResumePlainTextNormalizer.normalize(resumeText)
        let segments = CareerResumeSectionSegmenter.segment(normalizedText: normalized)

        XCTAssertFalse(resumeText.isEmpty, "Fixture failed to load")
        XCTAssertTrue(segments.contains { $0.kind == .education })
        XCTAssertTrue(segments.contains { $0.kind == .experience })
        XCTAssertTrue(segments.contains { $0.kind == .projects })
        XCTAssertTrue(segments.contains { $0.kind == .skills })

        let experienceText = CareerResumeSectionSegmenter.text(for: .experience, in: segments) ?? ""
        XCTAssertTrue(experienceText.localizedCaseInsensitiveContains("Insmed"))
        XCTAssertTrue(experienceText.localizedCaseInsensitiveContains("Project Destined"))
    }

    func testParser_skillGroupsFromCategorizedLines() {
        let text = """
        TECHNICAL SKILLS
        Security & Compliance: NIST SP 800-53, ISO 27001, SOC 2 Type II
        Tools: Wireshark, Nmap, Kali Linux
        """

        let profile = CareerResumeStructuredParser.parse(plainText: text)

        XCTAssertEqual(profile.skillGroups.count, 2)
        XCTAssertEqual(profile.skillGroups[0].category, "Security & Compliance")
        XCTAssertTrue(profile.skills.contains("NIST SP 800-53"))
        XCTAssertTrue(profile.skills.contains("Wireshark"))
    }

    func testParser_educationUsesInstitutionHeadingAndDetailBullets() {
        let text = """
        EDUCATION
        University at Buffalo - The State of New York Graduated: May 2026
        Bachelors of Science - Business Administration in Management Information Systems
        GPA: 3.5 / 4.0
        """

        let profile = CareerResumeStructuredParser.parse(plainText: text)

        XCTAssertEqual(profile.education.count, 1)
        XCTAssertTrue(profile.education[0].headingLines.first?.contains("University at Buffalo") == true)
        XCTAssertGreaterThanOrEqual(profile.education[0].bullets.count, 2)
        XCTAssertTrue(profile.education[0].bullets.contains { $0.localizedCaseInsensitiveContains("Bachelors") })
        XCTAssertTrue(profile.education[0].bullets.contains { $0.localizedCaseInsensitiveContains("GPA") })
    }

    func testParser_splitsTwoEducationInstitutions() {
        let text = """
        EDUCATION
        University at Buffalo - The State of New York
        Graduated: May 2026
        Bachelors of Science - Business Administration in Management Information Systems
        Dakota State University
        Graduated: May 2028
        Bachelor of Science - Cyber Leadership and Intelligence
        """

        let normalized = CareerResumePlainTextNormalizer.normalize(text)
        let profile = CareerResumeParseSanitizer.sanitize(
            CareerResumeStructuredParser.parse(plainText: normalized),
            sourceText: normalized
        )

        XCTAssertEqual(profile.education.count, 2)
        XCTAssertTrue(profile.education[0].headingLines.first?.contains("Buffalo") == true)
        XCTAssertTrue(profile.education[1].headingLines.first?.contains("Dakota State") == true)
    }

    func testHeuristicParser_digitalForensicsProjectHasBothBullets() {
        let normalized = CareerResumePlainTextNormalizer.normalize(resumeText)
        let profile = CareerResumeParseSanitizer.sanitize(
            CareerResumeStructuredParser.parse(plainText: normalized),
            sourceText: normalized
        )

        let forensics = profile.projects.first {
            $0.headingLines.joined(separator: " ").localizedCaseInsensitiveContains("Digital Forensics")
        }
        XCTAssertNotNil(forensics)
        XCTAssertEqual(forensics?.bullets.count, 2)
        XCTAssertTrue(forensics?.bullets.contains {
            $0.localizedCaseInsensitiveContains("Compiled disparate chronological logs")
        } == true)
    }

    func testEducationFields_renderStructuredLabels() {
        let entry = CareerResumeStructuredProfile.Entry(
            headingLines: ["University at Buffalo - The State of New York"],
            bullets: [
                "Graduated: May 2026",
                "Bachelors of Science - Business Administration in Management Information Systems",
                "GPA: 3.5 / 4.0; Awards: Magna Cum Laude",
                "Coursework: Systems Security, Digital Forensics",
            ]
        )

        let fields = CareerResumeParsedEntryDisplay.educationFields(from: entry)
        XCTAssertEqual(fields.institution, "University at Buffalo - The State of New York")
        XCTAssertEqual(fields.graduation, "Graduated: May 2026")
        XCTAssertTrue(fields.degree?.contains("Bachelors") == true)
        XCTAssertTrue(fields.gpa?.contains("3.5") == true)
        XCTAssertTrue(fields.coursework?.contains("Systems Security") == true)
    }

    func testExperienceDisplay_companyFirstHeadingOrder() {
        let entry = CareerResumeStructuredProfile.Entry(
            headingLines: [
                "Insmed Incorporated – Remote",
                "Cybersecurity Analyst Intern",
                "Security Governance, Risk, and Compliance (GRC) Focus June 2025 – August 2025",
            ],
            bullets: ["Assessed the information security risk posture of 60+ third-party vendors."]
        )

        let display = CareerResumeParsedEntryDisplay.experience(from: entry)
        XCTAssertEqual(display.organization, "Insmed Incorporated – Remote")
        XCTAssertEqual(display.title, "Cybersecurity Analyst Intern")
        XCTAssertEqual(display.dateLabel, "2025-06 → 2025-08")
    }
}
