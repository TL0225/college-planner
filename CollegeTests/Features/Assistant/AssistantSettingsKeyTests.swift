// AssistantSettingsKeyTests.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantSettingsKeyTests.
// Data: CollegePersistence / repositories when applicable.

import XCTest
@testable import College

final class AssistantSettingsKeyTests: XCTestCase {
    func testWritableKeys() {
        XCTAssertTrue(AssistantSettingsKey.isWritable(key: AssistantSettingsKey.streamingEnabled.rawValue))
        XCTAssertFalse(AssistantSettingsKey.isWritable(key: AssistantWebSearchSettings.searxBaseURLKey))
        XCTAssertFalse(AssistantSettingsKey.isWritable(key: AssistantPlannerIndexingSettings.indexingEnabledKey))
    }

    func testRejectedWriteReason() {
        XCTAssertNotNil(AssistantSettingsKey.rejectedWriteReason(for: AssistantWebSearchSettings.searxBaseURLKey))
    }
}
