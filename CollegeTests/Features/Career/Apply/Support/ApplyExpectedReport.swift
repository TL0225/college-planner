// ApplyExpectedReport.swift
// Feature: Career / Apply Tests

import Foundation
import Testing
@testable import College

struct ApplyExpectedReport: Decodable, Sendable {
    var fixture: String
    var attemptedPayloadKeys: [String]?
    var minWriteAttemptCount: Int?
    var maxWriteAttemptCount: Int?
}

enum ApplyExpectedReportLoader {
    static func load(named resource: String) throws -> ApplyExpectedReport {
        let url = try TestFixturePaths.applyExpected(named: resource)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ApplyExpectedReport.self, from: data)
    }

    static func assertMatchesExpected(_ report: CareerApplyVerificationReport, expected: ApplyExpectedReport) throws {
        if let maxWrites = expected.maxWriteAttemptCount {
            guard report.writeAttemptCount <= maxWrites else {
                throw ApplyFixtureError.writeCountExceeded(report.writeAttemptCount, maxWrites)
            }
        }
        if let minWrites = expected.minWriteAttemptCount {
            guard report.writeAttemptCount >= minWrites else {
                throw ApplyFixtureError.writeCountTooLow(report.writeAttemptCount, minWrites)
            }
        }
        if let keys = expected.attemptedPayloadKeys {
            for key in keys {
                guard let field = report.fields.first(where: { $0.payloadKey == key }) else {
                    throw ApplyFixtureError.missingField(key)
                }
                guard field.verified, field.status == .filled else {
                    throw ApplyFixtureError.unverifiedField(key, field.status.rawValue)
                }
            }
        }
    }
}

enum ApplyFixtureError: Error, CustomStringConvertible {
    case missingFixture(String)
    case missingField(String)
    case unverifiedField(String, String)
    case writeCountExceeded(Int, Int)
    case writeCountTooLow(Int, Int)
    case bridgeTimeout
    case reportTimeout

    var description: String {
        switch self {
        case .missingFixture(let name): return "Missing apply fixture: \(name)"
        case .missingField(let key): return "Expected field missing from report: \(key)"
        case .unverifiedField(let key, let status): return "Field not verified: \(key) status=\(status)"
        case .writeCountExceeded(let actual, let max): return "writeAttemptCount \(actual) > max \(max)"
        case .writeCountTooLow(let actual, let min): return "writeAttemptCount \(actual) < min \(min)"
        case .bridgeTimeout: return "Career apply bridge did not respond"
        case .reportTimeout: return "Career apply verification report not received"
        }
    }
}
