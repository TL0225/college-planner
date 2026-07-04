// LMSPortalConfigurationTests.swift
// Feature: App
// Purpose: LMS sidebar visibility respects onboarding selection.

import XCTest
@testable import College

final class LMSPortalConfigurationTests: XCTestCase {
    private let defaults = UserDefaults.standard

    override func tearDown() {
        defaults.removeObject(forKey: OnboardingPreferenceBridge.selectedLMSKey)
        defaults.removeObject(forKey: LMSPortalConfiguration.activeProviderKey)
        defaults.removeObject(forKey: "brightspace.portalURL")
        defaults.removeObject(forKey: LMSStorageKeys.lastVisitedURL)
        super.tearDown()
    }

    func testIsLMSTabEnabled_falseWhenOnboardingSkippedLMS() {
        defaults.set([], forKey: OnboardingPreferenceBridge.selectedLMSKey)
        XCTAssertFalse(LMSPortalConfiguration.isLMSTabEnabled())
    }

    func testIsLMSTabEnabled_trueWhenOnboardingSelectedBrightspace() {
        defaults.set(["Brightspace"], forKey: OnboardingPreferenceBridge.selectedLMSKey)
        XCTAssertTrue(LMSPortalConfiguration.isLMSTabEnabled())
    }

    func testResolvedPortalURL_nilWithoutConfiguredURL() {
        defaults.set(["Brightspace"], forKey: OnboardingPreferenceBridge.selectedLMSKey)
        XCTAssertNil(LMSPortalConfiguration.resolvedPortalURL())
    }

    func testApplyOnboardingLMSSelection_clearsActiveProviderWhenEmpty() {
        defaults.set("Brightspace", forKey: LMSPortalConfiguration.activeProviderKey)
        LMSPortalConfiguration.applyOnboardingLMSSelection([])
        XCTAssertNil(defaults.string(forKey: LMSPortalConfiguration.activeProviderKey))
    }
}
