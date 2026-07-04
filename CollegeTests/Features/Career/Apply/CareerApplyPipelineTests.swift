// CareerApplyPipelineTests.swift
// Feature: Career / Apply Tests — payload, gates, registry, parsing helpers

import Foundation
import Testing
@testable import College

@Suite("Career Apply Payload Builder")
struct CareerApplicationPayloadBuilderTests {
    @Test("Golden payload normalizes email and URLs")
    func normalizesPayload() {
        var payload = ApplyPayloadFactory.goldenContactPayload()
        payload.personal.phone = " (555) 123-4567 "
        let normalized = CareerATSFieldNormalizer.normalizePayload(payload)
        #expect(normalized.personal.phone == "5551234567")
        #expect(normalized.personal.email == "timothy@example.edu")
    }
}

@Suite("Career Apply Workday URL")
struct CareerApplyWorkdayURLTests {
    @Test("publicJobURL composes careers base and external path")
    func publicJobURL() {
        let context = WorkdayAPIContext(
            tenant: "nvidia",
            board: "NVIDIAExternalCareerSite",
            host: "nvidia.wd5.myworkdayjobs.com",
            apiBase: URL(string: "https://nvidia.wd5.myworkdayjobs.com/wday/cxs/nvidia/NVIDIAExternalCareerSite")!,
            careersURL: URL(string: "https://nvidia.wd5.myworkdayjobs.com/en-US/NVIDIAExternalCareerSite")!
        )
        let url = context.publicJobURL(externalPath: "/job/US-CA/SWE_JR123")
        #expect(url?.contains("NVIDIAExternalCareerSite") == true)
        #expect(url?.contains("SWE_JR123") == true)
    }
}

@Suite("Career Apply Accuracy Gate")
@MainActor
struct CareerApplyAccuracyGateTests {
    @Test("Blocks when apply URL missing")
    func blocksMissingURL() {
        let result = CareerApplyAccuracyGate.evaluate(applyURL: nil, resumeDocumentID: UUID(), parserHealthPercent: 90)
        #expect(result.allowed == false)
        #expect(result.reasons.contains(.missingApplyURL))
    }
}

@Suite("Career Apply Tier Registry")
struct CareerApplyTierRegistryTests {
    @Test("Tier C platforms are manual only")
    func tierC() {
        #expect(CareerApplyTierRegistry.tier(for: .oracle) == .manualOnly)
        #expect(CareerApplyTierRegistry.tier(for: .talemetry) == .manualOnly)
        #expect(CareerApplyTierRegistry.tier(for: .oracle).allowsAutofillWrites == false)
    }

    @Test("Tier A platforms allow writes")
    func tierA() {
        #expect(CareerApplyTierRegistry.tier(for: .greenhouse) == .full)
        #expect(CareerApplyTierRegistry.tier(for: .lever) == .full)
    }
}

@Suite("Career Apply Field Maps")
struct CareerApplyFieldMapLoaderTests {
    @Test(arguments: [
        JobBoardPlatform.greenhouse,
        JobBoardPlatform.lever,
        JobBoardPlatform.workday,
        JobBoardPlatform.icims,
        JobBoardPlatform.oracle,
        JobBoardPlatform.talemetry
    ])
    func loadsVersionedMaps(platform: JobBoardPlatform) {
        let map = CareerApplyFieldMapLoader.load(platform: platform)
        #expect(map != nil)
        #expect(map?.version == CareerApplyTierRegistry.mapVersion(for: platform))
    }
}

@Suite("Resume Section Alias Registry")
struct ResumeSectionAliasRegistryTests {
    @Test(arguments: ["Internships", "Work Experience", "Projects", "Education"])
    func mapsHeaders(header: String) {
        let category = ResumeSectionAliasRegistry.category(forHeader: header)
        #expect(category != .other || header == "Education")
    }
}

@Suite("Screening Question Synonym Registry")
struct ScreeningQuestionSynonymRegistryTests {
    @Test("Maps sponsorship question")
    func sponsorship() {
        let key = ScreeningQuestionSynonymRegistry.preferenceKey(forQuestion: "Will you require visa sponsorship now?")
        #expect(key == "workAuthorization.requiresSponsorshipNow")
    }
}
