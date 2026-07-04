// ATSScraperIdentifierTests.swift
// Feature: Career / Openings / Scrapers

import Foundation
import Testing
@testable import College

@Suite("ATSScraperIdentifierTests")
struct ATSScraperIdentifierTests {
    @Test("Greenhouse board token parses from board host and query links")
    func greenhouseBoardToken() {
        #expect(GreenhouseScraper.boardToken(from: "https://boards.greenhouse.io/acme") == "acme")
        #expect(GreenhouseScraper.boardToken(from: "https://job-boards.greenhouse.io/embed/job_app?for=acme") == "acme")
    }

    @Test("Lever company slug parses from board URL")
    func leverCompanySlug() {
        #expect(LeverScraper.companySlug(from: "https://jobs.lever.co/acme") == "acme")
        #expect(LeverScraper.companySlug(from: "https://lever.co/acme") == "acme")
    }

    @Test("ATS fingerprint detects remaining ATS platforms")
    func atsFingerprintDetection() {
        #expect(ATSFingerprintStore.detect(from: "https://example.oraclecloud.com/hcmUI/CandidateExperience") == .oracle)
        #expect(ATSFingerprintStore.detect(from: "https://careers-acme.icims.com/jobs") == .icims)
        #expect(ATSFingerprintStore.detect(from: "https://jobs.jobvite.com/acme") == .talemetry)
    }

    @Test("platform validation messages recognize ATS URLs")
    func platformValidationMessages() {
        #expect(
            JobBoardPlatformDetector.validationMessage(
                for: "https://example.oraclecloud.com/hcmUI/CandidateExperience",
                platform: .oracle
            ).ok
        )
        #expect(
            JobBoardPlatformDetector.validationMessage(
                for: "https://careers-acme.icims.com/jobs",
                platform: .icims
            ).ok
        )
        #expect(
            JobBoardPlatformDetector.validationMessage(
                for: "https://jobs.jobvite.com/acme",
                platform: .talemetry
            ).ok
        )
    }
}
