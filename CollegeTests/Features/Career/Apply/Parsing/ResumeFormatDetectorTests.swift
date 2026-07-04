// ResumeFormatDetectorTests.swift
// Feature: Career / Apply Tests

import Testing
@testable import College

@Suite("Resume Format Detector")
struct ResumeFormatDetectorTests {
    @Test("Detects chronological student resume")
    func chronologicalFixture() throws {
        let url = try TestFixturePaths.url("Apply/Resumes/golden_chronological.txt")
        let plain = try String(contentsOf: url, encoding: .utf8)
        let kind = ResumeFormatDetector.detect(
            plainText: plain,
            sections: ["WORK EXPERIENCE", "EDUCATION", "SKILLS"]
        )
        #expect(kind == .chronological || kind == .hybrid)
    }
}
