// WorkdayURLContextTests.swift
// Feature: Career / Openings / Scrapers

import Foundation
import Testing
@testable import College

@Suite("WorkdayURLContextTests")
struct WorkdayURLContextTests {
    @Test("delay nanoseconds converts milliseconds")
    func delayNanoseconds() {
        #expect(WorkdayScraper.delayNanoseconds(forMilliseconds: 1_500) == 1_500_000_000)
        #expect(WorkdayScraper.delayNanoseconds(forMilliseconds: 0) == 0)
    }

    @Test("normalize careers URL strips detail tails and jobs suffix")
    func normalizeCareersURL() {
        #expect(
            WorkdayScraper.normalizeCareersURLString(
                "https://nvidia.wd5.myworkdayjobs.com/en-US/NVIDIAExternalCareerSite/job/US-CA-Santa-Clara/Role_JR123"
            ) == "https://nvidia.wd5.myworkdayjobs.com/en-US/NVIDIAExternalCareerSite"
        )
        #expect(
            WorkdayScraper.normalizeCareersURLString(
                "https://insmed.wd5.myworkdayjobs.com/en-US/EXTERNAL/jobs"
            ) == "https://insmed.wd5.myworkdayjobs.com/en-US/EXTERNAL"
        )
    }

    @Test("derive API context from board URL")
    func deriveAPIContext() {
        let ctx = WorkdayScraper.deriveAPIContext(
            careersURLString: "https://nvidia.wd5.myworkdayjobs.com/en-US/NVIDIAExternalCareerSite"
        )
        #expect(ctx?.tenant == "nvidia")
        #expect(ctx?.board == "NVIDIAExternalCareerSite")
        #expect(
            ctx?.listJobsURL?.absoluteString
                == "https://nvidia.wd5.myworkdayjobs.com/wday/cxs/nvidia/NVIDIAExternalCareerSite/jobs"
        )
    }

    @Test("derive API context recognizes uppercase locale prefix")
    func uppercaseLocalePrefix() {
        let ctx = WorkdayScraper.deriveAPIContext(
            careersURLString: "https://insmed.wd5.myworkdayjobs.com/EN-US/EXTERNAL"
        )
        #expect(ctx?.board == "EXTERNAL")
    }

    @Test("detail URL preserves job path segments")
    func detailURL() {
        let ctx = try! #require(WorkdayScraper.deriveAPIContext(
            careersURLString: "https://nvidia.wd5.myworkdayjobs.com/en-US/NVIDIAExternalCareerSite"
        ))
        let detail = ctx.detailURL(
            externalPath: "/en-US/NVIDIAExternalCareerSite/job/US-CA-Santa-Clara/Senior-Solutions-Architect_JR2017438-1"
        )
        #expect(
            detail?.absoluteString
                == "https://nvidia.wd5.myworkdayjobs.com/wday/cxs/nvidia/NVIDIAExternalCareerSite/job/US-CA-Santa-Clara/Senior-Solutions-Architect_JR2017438-1"
        )
    }

    @Test("embedded config and discovery parse board URLs")
    func embeddedConfigAndDiscovery() {
        let html = """
        tenant:
        "insmed",
        siteId:   "EXTERNAL",
        <a href="https://insmed.wd5.myworkdayjobs.com/en-US/EXTERNAL/introduceYourself">Join talent community</a>
        """
        let parsed = WorkdayScraper.parseEmbeddedSiteConfig(from: html)
        #expect(parsed?.tenant == "insmed")
        #expect(parsed?.siteId == "EXTERNAL")
        #expect(
            WorkdayScraper.discoverWorkdayBoardURL(from: html)
                == "https://insmed.wd5.myworkdayjobs.com/en-US/EXTERNAL"
        )
    }

    @Test("locale segment rejects job route segments")
    func localeSegment() {
        #expect(!WorkdayScraper.isLocaleSegment("job"))
        #expect(!WorkdayScraper.isLocaleSegment("jobs"))
        #expect(WorkdayScraper.isLocaleSegment("en-US"))
    }
}
