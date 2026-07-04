// CareerApplicationPreferences.swift
// Feature: Career / ApplicationProfile
// Purpose: User-declared work authorization, screening answers, and apply defaults.

import Foundation
import SwiftData

@Model
final class CareerApplicationPreferences {
    @Attribute(.unique) var id: UUID
    var updatedAt: Date

    var usCitizen: Bool?
    var usAuthorized: Bool?
    var requiresSponsorshipNow: Bool?
    var requiresSponsorshipFuture: Bool?
    var countryOfCitizenship: String?
    var visaStatus: String?

    var willingToRelocate: String?
    var remotePreference: String?
    var salaryExpectation: String?
    var earliestStartDate: String?
    var referralSource: String?

    var allowEEOAutofill: Bool
    /// Stored generation marker so V1_8 schema checksum differs from V1_6 (avoid staged-migration duplicate checksum crash).
    var applyProfileSchemaGeneration: Int
    /// JSON map: question hash → ApplyScreeningAnswer
    var screeningCacheJSON: String?

    init(
        id: UUID = UUID(),
        updatedAt: Date = .now,
        usCitizen: Bool? = nil,
        usAuthorized: Bool? = nil,
        requiresSponsorshipNow: Bool? = nil,
        requiresSponsorshipFuture: Bool? = nil,
        countryOfCitizenship: String? = nil,
        visaStatus: String? = nil,
        willingToRelocate: String? = nil,
        remotePreference: String? = nil,
        salaryExpectation: String? = nil,
        earliestStartDate: String? = nil,
        referralSource: String? = nil,
        allowEEOAutofill: Bool = false,
        applyProfileSchemaGeneration: Int = 1,
        screeningCacheJSON: String? = nil
    ) {
        self.id = id
        self.updatedAt = updatedAt
        self.usCitizen = usCitizen
        self.usAuthorized = usAuthorized
        self.requiresSponsorshipNow = requiresSponsorshipNow
        self.requiresSponsorshipFuture = requiresSponsorshipFuture
        self.countryOfCitizenship = countryOfCitizenship
        self.visaStatus = visaStatus
        self.willingToRelocate = willingToRelocate
        self.remotePreference = remotePreference
        self.salaryExpectation = salaryExpectation
        self.earliestStartDate = earliestStartDate
        self.referralSource = referralSource
        self.allowEEOAutofill = allowEEOAutofill
        self.applyProfileSchemaGeneration = applyProfileSchemaGeneration
        self.screeningCacheJSON = screeningCacheJSON
    }

    func decodedScreeningCache() -> [String: ApplyScreeningAnswer] {
        guard let screeningCacheJSON,
              let data = screeningCacheJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: ApplyScreeningAnswer].self, from: data) else {
            return [:]
        }
        return decoded
    }

    func encodeScreeningCache(_ cache: [String: ApplyScreeningAnswer]) {
        screeningCacheJSON = (try? JSONEncoder().encode(cache)).flatMap { String(data: $0, encoding: .utf8) }
    }
}
