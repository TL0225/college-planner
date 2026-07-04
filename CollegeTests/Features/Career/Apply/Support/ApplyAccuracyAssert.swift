// ApplyAccuracyAssert.swift
// Feature: Career / Apply Tests

import Foundation
import Testing
@testable import College

enum ApplyAccuracyAssert {
    static func requirePerfectVerifyPass(_ report: CareerApplyVerificationReport) {
        let attempted = report.fields.filter {
            $0.status != .skipped && $0.status != .ambiguous && $0.status != .manualOnly
        }
        for field in attempted {
            #expect(field.verified == true, "wrong_value: \(field.payloadKey) intended=\(field.intended) filled=\(field.filled ?? "nil")")
        }
        #expect(report.wrongValueCount == 0)
        let passRate = attempted.isEmpty ? 1.0 : Double(attempted.filter(\.verified).count) / Double(attempted.count)
        #expect(passRate == 1.0, "verify pass rate must be 100% on attempted fields")
    }

    static func requireZeroWrites(_ report: CareerApplyVerificationReport) {
        #expect(report.writeAttemptCount == 0)
        let writes = report.fields.filter { $0.status == .filled }
        #expect(writes.isEmpty)
    }

    static func requireNoEEOWrites(_ report: CareerApplyVerificationReport) {
        let eeo = report.fields.filter { $0.payloadKey.lowercased().contains("eeo") }
        #expect(eeo.allSatisfy { $0.status != .filled })
    }
}
