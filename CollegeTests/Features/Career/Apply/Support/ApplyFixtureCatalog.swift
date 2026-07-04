// ApplyFixtureCatalog.swift
// Feature: Career / Apply Tests

import Foundation
@testable import College

struct ApplyFixtureCase: Sendable, Hashable {
    var name: String
    var htmlResource: String
    var platform: JobBoardPlatform
    var tier: CareerApplyTier
    var expectedResource: String
}

enum ApplyFixtureCatalog {
    static let greenhouseCases: [ApplyFixtureCase] = [
        ApplyFixtureCase(
            name: "greenhouse_contact",
            htmlResource: "greenhouse_contact",
            platform: .greenhouse,
            tier: .full,
            expectedResource: "greenhouse_contact"
        )
    ]
    static let leverCases: [ApplyFixtureCase] = [
        ApplyFixtureCase(
            name: "lever_contact",
            htmlResource: "lever_contact",
            platform: .lever,
            tier: .full,
            expectedResource: "lever_contact"
        )
    ]
    static let workdayCases: [ApplyFixtureCase] = [
        ApplyFixtureCase(
            name: "workday_contact",
            htmlResource: "workday_contact",
            platform: .workday,
            tier: .partial,
            expectedResource: "workday_contact"
        )
    ]
    static let icimsCases: [ApplyFixtureCase] = [
        ApplyFixtureCase(
            name: "icims_contact",
            htmlResource: "icims_contact",
            platform: .icims,
            tier: .partial,
            expectedResource: "icims_contact"
        )
    ]
    static let oracleCases: [ApplyFixtureCase] = [
        ApplyFixtureCase(
            name: "oracle_inventory",
            htmlResource: "oracle_inventory",
            platform: .oracle,
            tier: .manualOnly,
            expectedResource: "oracle_inventory"
        )
    ]
    static let talemetryCases: [ApplyFixtureCase] = [
        ApplyFixtureCase(
            name: "talemetry_inventory",
            htmlResource: "talemetry_inventory",
            platform: .talemetry,
            tier: .manualOnly,
            expectedResource: "talemetry_inventory"
        )
    ]

    static let allAutofillCases: [ApplyFixtureCase] =
        greenhouseCases + leverCases + workdayCases + icimsCases

    static let allTierCCases: [ApplyFixtureCase] = oracleCases + talemetryCases
}
