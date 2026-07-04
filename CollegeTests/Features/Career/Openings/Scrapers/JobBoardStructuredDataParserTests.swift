// JobBoardStructuredDataParserTests.swift
// Feature: Career / Openings / Scrapers

import Testing
@testable import College

@Suite("JobBoardStructuredDataParserTests")
struct JobBoardStructuredDataParserTests {
    @Test("Extracts JobPosting from JSON-LD")
    func extractsJobPosting() throws {
        let html = try TestFixturePaths.jobBoardString(platform: "BuiltIn", named: "builtin-job-detail.html")
        let posting = JobBoardStructuredDataParser.firstJobPosting(in: html)
        #expect(posting?.title == "Software Engineer")
        #expect(posting?.descriptionPlain?.contains("Swift") == true)
        #expect(posting?.datePosted == "2026-06-01")
    }
}
