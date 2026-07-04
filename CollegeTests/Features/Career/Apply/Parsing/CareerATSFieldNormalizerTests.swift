// CareerATSFieldNormalizerTests.swift
// Feature: Career / Apply Tests

import Testing
@testable import College

@Suite("Career ATS Field Normalizer")
struct CareerATSFieldNormalizerTests {
    @Test("Normalizes phone digits and URL scheme")
    func normalizesContactFields() {
        #expect(CareerATSFieldNormalizer.normalizePhone("(555) 123-4567") == "5551234567")
        #expect(CareerATSFieldNormalizer.normalizeURL("linkedin.com/in/timothy") == "https://linkedin.com/in/timothy")
        #expect(CareerATSFieldNormalizer.expandAcronym("CPA", aliases: ["CPA": "Certified Public Accountant"]) == "Certified Public Accountant")
    }
}
