// WorkdayScraperTests.swift
// Feature: Career
// Purpose: Workday URL derivation, decoder, and scraper helper regressions.

import XCTest
@testable import College

final class WorkdayScraperTests: XCTestCase {
    func testDelayNanosecondsConvertsMilliseconds() {
        XCTAssertEqual(WorkdayScraper.delayNanoseconds(forMilliseconds: 1_500), 1_500_000_000)
        XCTAssertEqual(WorkdayScraper.delayNanoseconds(forMilliseconds: 0), 0)
    }

    func testNormalizeCareersURLStripsJobDetailTail() {
        let raw = "https://nvidia.wd5.myworkdayjobs.com/en-US/NVIDIAExternalCareerSite/job/US-CA-Santa-Clara/Role_JR123"
        let normalized = WorkdayScraper.normalizeCareersURLString(raw)
        XCTAssertEqual(
            normalized,
            "https://nvidia.wd5.myworkdayjobs.com/en-US/NVIDIAExternalCareerSite"
        )
    }

    func testNormalizeCareersURLStripsCapitalJobDetailTail() {
        let raw = "https://nvidia.wd5.myworkdayjobs.com/en-US/NVIDIAExternalCareerSite/Job/US-CA-Santa-Clara/Role_JR123"
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
        XCTAssertEqual(
            ctx?.listJobsURL?.absoluteString,
            "https://insmed.wd5.myworkdayjobs.com/wday/cxs/insmed/EXTERNAL/jobs"
        )
    }

    func testDeriveAPIContextFromBoardURL() {
        let ctx = WorkdayScraper.deriveAPIContext(
            careersURLString: "https://nvidia.wd5.myworkdayjobs.com/en-US/NVIDIAExternalCareerSite"
        )
        XCTAssertNotNil(ctx)
        XCTAssertEqual(ctx?.tenant, "nvidia")
        XCTAssertEqual(ctx?.board, "NVIDIAExternalCareerSite")
        XCTAssertEqual(
            ctx?.listJobsURL?.absoluteString,
            "https://nvidia.wd5.myworkdayjobs.com/wday/cxs/nvidia/NVIDIAExternalCareerSite/jobs"
        )
    }

    func testDeriveAPIContextRecognizesUppercaseLocalePrefix() {
        let ctx = WorkdayScraper.deriveAPIContext(
            careersURLString: "https://insmed.wd5.myworkdayjobs.com/EN-US/EXTERNAL"
        )
        XCTAssertNotNil(ctx)
        XCTAssertEqual(ctx?.board, "EXTERNAL")
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

    func testDetailURLPreservesJobSegmentForInsmedListingPath() {
        let ctx = WorkdayScraper.deriveAPIContext(
            careersURLString: "https://insmed.wd5.myworkdayjobs.com/en-US/EXTERNAL"
        )!
        let detail = ctx.detailURL(
            externalPath: "/job/NJ-Corporate-Headquarters/Head-of-Clinical-Data-Management_R3498"
        )
        XCTAssertEqual(
            detail?.absoluteString,
            "https://insmed.wd5.myworkdayjobs.com/wday/cxs/insmed/EXTERNAL/job/NJ-Corporate-Headquarters/Head-of-Clinical-Data-Management_R3498"
        )
    }

    func testIsLocaleSegmentRejectsJobRouteSegment() {
        XCTAssertFalse(WorkdayScraper.isLocaleSegment("job"))
        XCTAssertFalse(WorkdayScraper.isLocaleSegment("jobs"))
        XCTAssertTrue(WorkdayScraper.isLocaleSegment("en-US"))
    }

    func testDetailURLStripsLocaleAndBoardPrefixFromExternalPath() {
        let ctx = WorkdayScraper.deriveAPIContext(
            careersURLString: "https://nvidia.wd5.myworkdayjobs.com/en-US/NVIDIAExternalCareerSite"
        )!
        let detail = ctx.detailURL(
            externalPath: "/en-US/NVIDIAExternalCareerSite/job/US-CA-Santa-Clara/Senior-Solutions-Architect_JR2017438-1"
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

    func testParseEmbeddedSiteConfigAllowsWhitespaceAfterColon() {
        let html = """
        tenant:
        "insmed",
        siteId:   "EXTERNAL",
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

    func testDiscoverWorkdayBoardURLStopsAtWhitespace() {
        let html = """
        <a href="https://insmed.wd5.myworkdayjobs.com/en-US/EXTERNAL introduce">bad</a>
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

    func testWorkdayListResponseDecoderRejectsAPIErrorWithoutJobPostingsKey() {
        let json = #"{"errorCode":"INVALID_SESSION","message":"Session expired"}"#
        XCTAssertThrowsError(try WorkdayJobListResponseDecoder.decode(from: Data(json.utf8)))
    }

    func testWorkdayListResponseDecoderAcceptsListWhenErrorCodePresentWithJobPostings() throws {
        let json = """
        {
          "errorCode": "",
          "total": 1,
          "jobPostings": [
            {
              "title": "Engineer",
              "externalPath": "/job/Title_R1"
            }
          ]
        }
        """
        let decoded = try WorkdayJobListResponseDecoder.decode(from: Data(json.utf8))
        XCTAssertEqual(decoded.jobPostings.count, 1)
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

    func testDuplicateExternalPathUniquingKeepsLatestJob() {
        let first = WorkdayScrapedJob(
            title: "Old",
            externalPath: "/job/A_R1",
            locationsText: nil,
            postedOn: nil,
            bulletFields: nil
        )
        let second = WorkdayScrapedJob(
            title: "New",
            externalPath: "/job/A_R1",
            locationsText: "Remote",
            postedOn: nil,
            bulletFields: nil
        )
        let byPath = Dictionary(
            [first, second].map { ($0.externalPath, $0) },
            uniquingKeysWith: { _, new in new }
        )
        XCTAssertEqual(byPath["/job/A_R1"]?.title, "New")
    }

    func testFacetTaggedJobsPreserveListingOrder() {
        let jobs = [
            WorkdayScrapedJob(title: "B", externalPath: "/b", locationsText: nil, postedOn: nil, bulletFields: nil),
            WorkdayScrapedJob(title: "A", externalPath: "/a", locationsText: nil, postedOn: nil, bulletFields: nil),
        ]
        var byPath = Dictionary(jobs.map { ($0.externalPath, $0) }, uniquingKeysWith: { _, new in new })
        byPath["/b"]?.jobTypeText = "Regular"
        byPath["/a"]?.jobTypeText = "Regular"
        let ordered = jobs.map { byPath[$0.externalPath] ?? $0 }
        XCTAssertEqual(ordered.map(\.title), ["B", "A"])
    }

    func testJobBoardHTTPHtmlToPlainPreservesParagraphBreaks() {
        let html = "<p>First paragraph.</p><p>Second paragraph.</p>"
        let plain = JobBoardHTTP.htmlToPlain(html)
        XCTAssertTrue(plain.contains("First paragraph."))
        XCTAssertTrue(plain.contains("Second paragraph."))
        XCTAssertTrue(plain.contains("\n"))
    }

    func testWorkdayJobPostingInfoDecodesObjectShapedAdditionalLocations() throws {
        let json = """
        {
          "title": "Role",
          "jobDescription": "<p>Hello</p>",
          "additionalLocations": [
            { "location": "Boston" },
            { "location": "NYC" }
          ]
        }
        """
        let info = try JSONDecoder().decode(WorkdayJobPostingInfo.self, from: Data(json.utf8))
        XCTAssertEqual(info.additionalLocations, ["Boston", "NYC"])
    }

    func testWorkdayJobPostingInfoDecodesSalaryFields() throws {
        let json = """
        {
          "title": "Role",
          "jobDescription": "desc",
          "payRange": "$120,000 - $150,000"
        }
        """
        let info = try JSONDecoder().decode(WorkdayJobPostingInfo.self, from: Data(json.utf8))
        XCTAssertEqual(info.salaryRangeText, "$120,000 - $150,000")
    }

    func testWorkdayScraperErrorMapsNetworkToJobBoardNetwork() {
        let mapped = WorkdayScraperError.network("offline").asJobBoardError
        XCTAssertEqual(mapped, .network("offline"))
    }

    func testNormalizeListingExternalPathStripsLocaleAndBoard() {
        let normalized = WorkdayScraper.normalizeListingExternalPath(
            "/en-US/NVIDIAExternalCareerSite/job/US-CA-Santa-Clara/Role_JR1",
            board: "NVIDIAExternalCareerSite"
        )
        XCTAssertEqual(normalized, "/job/US-CA-Santa-Clara/Role_JR1")
    }

    func testThrowIfMaintenancePageDetectsWorkdayMaintenanceRedirect() {
        let html = """
        <html><head><script>window.location.href = "https://community.workday.com/maintenance-page"</script></head></html>
        """
        XCTAssertThrowsError(try WorkdayScraper.throwIfMaintenancePage(html: html)) { error in
            guard let workdayError = error as? WorkdayScraperError,
                  case .network(let detail) = workdayError else {
                return XCTFail("Expected network error, got \(error)")
            }
            XCTAssertTrue(detail.localizedCaseInsensitiveContains("maintenance"))
        }
    }
}
