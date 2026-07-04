// AssistantSettingsKeyTests.swift
// Assistant settings keys (Swift Testing).

import Foundation
import Testing
@testable import College

@Suite("Assistant Settings Keys")
struct AssistantSettingsKeyTests {

    @Test("Writable keys")
    func writableKeys() {
        #expect(AssistantSettingsKey.isWritable(key: AssistantSettingsKey.streamingEnabled.rawValue))
        #expect(!AssistantSettingsKey.isWritable(key: AssistantWebSearchSettings.customBaseURLKey))
        #expect(!AssistantSettingsKey.isWritable(key: AssistantPlannerIndexingSettings.indexingEnabledKey))
    }

    @Test("Rejected write reason")
    func rejectedWriteReason() {
        #expect(AssistantSettingsKey.rejectedWriteReason(for: AssistantWebSearchSettings.customBaseURLKey) != nil)
    }
}
