// WorkdayScraperTests.swift
// Feature: Career
// Purpose: Workday URL derivation and detail endpoint construction.

import XCTest
@testable import College

final class WorkdayScraperTests: XCTestCase {
    func testNormalizeCareersURLStripsJobDetailTail() {
        let raw = "https://nvidia.wd5.myworkdayjobs.com/en-US/NVIDIAExternalCareerSite/job/US-CA-Santa-Clara/Role_JR123"
        let normalized = WorkdayScraper.normalizeCareersURLString(raw)
        XCTAssertEqual(
            normalized,
            "https://nvidia.wd5.myworkdayjobs.com/en-US/NVIDIAExternalCareerSite"
        )
    }

    func testNormalizeCareersURLStripsTrailingJobsAPIPath() {
        let raw = "https://insmed.wd5.myworkdayjobs.com/en-US/EXTERNAL/jobs"
        let normalized = WorkdayScraper.normalizeCareersURLString(raw)
        XCTAssertEqual(
            normalized,
            "https://insmed.wd5.myworkdayjobs.com/en-US/EXTERNAL"
        )
        let ctx = WorkdayScraper.deriveAPIContext(careersURLString: normalized)
        XCTAssertEqual(ctx?.listJobsURL.absoluteString, "https://insmed.wd5.myworkdayjobs.com/wday/cxs/insmed/EXTERNAL/jobs")
    }

    func testDeriveAPIContextFromBoardURL() {
        let ctx = WorkdayScraper.deriveAPIContext(
            careersURLString: "https://nvidia.wd5.myworkdayjobs.com/en-US/NVIDIAExternalCareerSite"
        )
        XCTAssertNotNil(ctx)
        XCTAssertEqual(ctx?.tenant, "nvidia")
        XCTAssertEqual(ctx?.board, "NVIDIAExternalCareerSite")
        XCTAssertEqual(
            ctx?.listJobsURL.absoluteString,
            "https://nvidia.wd5.myworkdayjobs.com/wday/cxs/nvidia/NVIDIAExternalCareerSite/jobs"
        )
    }

    func testDetailURLAppendsExternalPathSegments() {
        let ctx = WorkdayScraper.deriveAPIContext(
            careersURLString: "https://nvidia.wd5.myworkdayjobs.com/en-US/NVIDIAExternalCareerSite"
        )!
        let detail = ctx.detailURL(
            externalPath: "/job/US-CA-Santa-Clara/Senior-Solutions-Architect_JR2017438-1"
        )
        XCTAssertEqual(
            detail?.absoluteString,
            "https://nvidia.wd5.myworkdayjobs.com/wday/cxs/nvidia/NVIDIAExternalCareerSite/job/US-CA-Santa-Clara/Senior-Solutions-Architect_JR2017438-1"
        )
    }

    func testParseEmbeddedSiteConfigFromHTMLSnippet() {
        let html = """
        tenant: "insmed",
        siteId: "EXTERNAL",
        """
        let parsed = WorkdayScraper.parseEmbeddedSiteConfig(from: html)
        XCTAssertEqual(parsed?.tenant, "insmed")
        XCTAssertEqual(parsed?.siteId, "EXTERNAL")
    }

    func testDiscoverWorkdayBoardURLFromCustomDomainHTML() {
        let html = """
        <a href="https://insmed.wd5.myworkdayjobs.com/en-US/EXTERNAL/introduceYourself">Join talent community</a>
        """
        let discovered = WorkdayScraper.discoverWorkdayBoardURL(from: html)
        XCTAssertEqual(
            discovered,
            "https://insmed.wd5.myworkdayjobs.com/en-US/EXTERNAL"
        )
    }

    func testDeriveAPIContextForInsmedBoardURL() {
        let ctx = WorkdayScraper.deriveAPIContext(
            careersURLString: "https://insmed.wd5.myworkdayjobs.com/en-US/EXTERNAL"
        )
        XCTAssertNotNil(ctx)
        XCTAssertEqual(ctx?.tenant, "insmed")
        XCTAssertEqual(ctx?.board, "EXTERNAL")
    }

    func testWorkdayListResponseDecoderAcceptsPartialPayload() throws {
        let data = Data("{\"jobPostings\":[]}".utf8)
        let decoded = try WorkdayJobListResponseDecoder.decode(from: data)
        XCTAssertEqual(decoded.total, 0)
        XCTAssertTrue(decoded.jobPostings.isEmpty)
    }

    func testWorkdayListResponseDecoderRejectsEmptyObject() {
        XCTAssertThrowsError(try WorkdayJobListResponseDecoder.decode(from: Data("{}".utf8)))
    }

    func testWorkdayListResponseDecoderAcceptsNestedLocationFacets() throws {
        let json = """
        {
          "total": 88,
          "jobPostings": [
            {
              "title": "Head of Clinical Data Management",
              "externalPath": "/job/NJ-Corporate-Headquarters/Head-of-Clinical-Data-Management_R3498",
              "locationsText": "NJ Corporate Headquarters",
              "postedOn": "Posted Today",
              "bulletFields": ["R3498"]
            }
          ],
          "facets": [
            {
              "facetParameter": "workerSubType",
              "descriptor": "Job Type",
              "values": [
                { "descriptor": "Regular", "id": "1d652c5d27f61000a681c0b241620000", "count": 88 }
              ]
            },
            {
              "facetParameter": "locationMainGroup",
              "values": [
                {
                  "facetParameter": "locationCountry",
                  "descriptor": "Location Country",
                  "values": [
                    { "descriptor": "United States of America", "id": "bc33aa3152ec42d4995f4791a106ed09", "count": 77 }
                  ]
                }
              ]
            }
          ],
          "userAuthenticated": false
        }
        """
        let decoded = try WorkdayJobListResponseDecoder.decode(from: Data(json.utf8))
        XCTAssertEqual(decoded.total, 88)
        XCTAssertEqual(decoded.jobPostings.count, 1)
        XCTAssertEqual(decoded.facets?.count, 2)
        XCTAssertEqual(decoded.facets?.last?.facetParameter, "locationMainGroup")
        XCTAssertEqual(decoded.facets?.last?.values?.first?.descriptor, "United States of America")
    }

    func testShouldApplyFacetTagInMemoryWhenBucketCoversBoard() {
        let value = WorkdayFacetValue(descriptor: "Regular", id: "abc", count: 88)
        XCTAssertTrue(WorkdayScraper.shouldApplyFacetTagInMemory(value: value, jobCount: 88))
        XCTAssertFalse(WorkdayScraper.shouldApplyFacetTagInMemory(value: value, jobCount: 40))
    }

    func testApplyFacetTagInMemorySetsJobTypeAndTimeType() {
        var jobs = [
            "/a": WorkdayScrapedJob(
                title: "A",
                externalPath: "/a",
                locationsText: nil,
                postedOn: nil,
                bulletFields: nil
            ),
        ]
        WorkdayScraper.applyFacetTagInMemory(
            value: WorkdayFacetValue(descriptor: "Regular", id: "1", count: 1),
            facetParameter: "workerSubType",
            jobsByPath: &jobs
        )
        XCTAssertEqual(jobs["/a"]?.jobTypeText, "Regular")

        WorkdayScraper.applyFacetTagInMemory(
            value: WorkdayFacetValue(descriptor: "Full time", id: "2", count: 1),
            facetParameter: "timeType",
            jobsByPath: &jobs
        )
        XCTAssertEqual(jobs["/a"]?.timeType, "Full time")
    }
}
