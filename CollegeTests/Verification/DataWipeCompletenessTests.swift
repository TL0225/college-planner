// DataWipeCompletenessTests.swift
// Snow Leopard V&V: wipe clears LMS Keychain credentials (SEC2, CP5).

import XCTest
@testable import College

@MainActor
final class DataWipeCompletenessTests: XCTestCase {
    func testLMSKeychainDeleteAllClearsSavedCredentials() {
        let service = LMSKeychainService.shared
        XCTAssertTrue(service.save(username: "student", password: "secret", host: "wipe-test.example.edu"))
        XCTAssertNotNil(service.load(host: "wipe-test.example.edu"))

        XCTAssertTrue(service.deleteAll())
        XCTAssertNil(service.load(host: "wipe-test.example.edu"))
    }
}
