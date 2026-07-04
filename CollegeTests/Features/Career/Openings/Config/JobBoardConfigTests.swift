// JobBoardConfigTests.swift
// Feature: Career / Openings / Config

import Foundation
import Testing
@testable import College

@Suite("JobBoardConfigTests")
struct JobBoardConfigTests {
    @Test("Slugify normalizes company names")
    @MainActor
    func slugify() {
        #expect(JobBoardCompaniesStore.slugify("NVIDIA Corp.") == "nvidia-corp")
    }

    @Test(arguments: [
        ("https://nvidia.wd5.myworkdayjobs.com/en-US/NVIDIAExternalCareerSite", JobBoardPlatform.workday),
        ("https://boards.greenhouse.io/acme", JobBoardPlatform.greenhouse),
        ("https://jobs.lever.co/acme", JobBoardPlatform.lever),
        ("https://example.oraclecloud.com/hcmUI/CandidateExperience", JobBoardPlatform.oracle),
        ("https://careers-acme.icims.com/jobs", JobBoardPlatform.icims),
        ("https://jobs.jobvite.com/acme", JobBoardPlatform.talemetry),
        ("https://builtin.com/jobs", JobBoardPlatform.builtIn),
        ("https://jobicy.com/remote-jobs", JobBoardPlatform.jobicy),
        ("https://remoteok.com", JobBoardPlatform.remoteOK),
        ("https://www.ycombinator.com/jobs", JobBoardPlatform.yCombinator),
        ("https://www.usajobs.gov/Search/Results", JobBoardPlatform.usajobs),
        ("https://cityjobs.nyc.gov/jobs", JobBoardPlatform.nycCityJobs),
        ("https://statejobs.ny.gov/public/vacancyTable.cfm", JobBoardPlatform.nyStateJobs),
    ])
    func platformDetection(url: String, expected: JobBoardPlatform) {
        #expect(JobBoardPlatformDetector.detect(from: url) == expected)
    }

    @Test("Invalid URL returns nil platform")
    func invalidURL() {
        #expect(JobBoardPlatformDetector.detect(from: "not-a-url") == nil)
    }

    @Test("Workday validation accepts myworkdayjobs host")
    func workdayValidation() {
        let result = JobBoardPlatformDetector.validationMessage(
            for: "https://acme.wd1.myworkdayjobs.com/Acme_Careers",
            platform: .workday
        )
        #expect(result.ok == true)
    }
}
