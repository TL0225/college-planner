// LMSKeychainRoundTripTests.swift
// Snow Leopard flow #6: LMS credential store → restore.

import XCTest
@testable import College

@MainActor
final class LMSKeychainRoundTripTests: XCTestCase {
    func testSaveLoadDeleteRoundTrip() {
        let service = LMSKeychainService.shared
        let host = "lms-roundtrip.example.edu"
        XCTAssertTrue(service.save(username: "alice", password: "pw", host: host))

        let loaded = service.load(host: host)
        XCTAssertEqual(loaded?.username, "alice")
        XCTAssertEqual(loaded?.password, "pw")

        XCTAssertTrue(service.delete(host: host))
        XCTAssertNil(service.load(host: host))
    }
}
