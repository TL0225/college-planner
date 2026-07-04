// AssistantConversationPersistenceTests.swift
// Layer 0 — conversation store round-trip (Swift Testing).

import Foundation
import Testing
@testable import College

@Suite("Assistant Conversation Persistence")
struct AssistantConversationPersistenceTests {

    private func uniqueTestKey() -> String {
        "assistant.messages.v1.test.\(UUID().uuidString)"
    }

    @Test("Persisted messages round-trip through UserDefaults")
    func persistedMessagesRoundTrip() {
        let testStoreKey = uniqueTestKey()
        defer { UserDefaults.standard.removeObject(forKey: testStoreKey) }
        let original = [
            PersistedAssistantMessage(
                id: UUID(),
                isUser: true,
                roleRawValue: AssistantAgentRole.academicAdvisor.rawValue,
                text: "What is my major?",
                timestamp: Date(),
                attachmentDisplayNames: nil,
                modelPromptOverride: nil,
                attachmentContextBlock: nil,
                sources: nil,
                toolTrace: nil,
                feedbackRaw: nil,
                supersededReplyTexts: nil
            ),
            PersistedAssistantMessage(
                id: UUID(),
                isUser: false,
                roleRawValue: AssistantAgentRole.academicAdvisor.rawValue,
                text: "Your major is Computer Science.",
                timestamp: Date(),
                attachmentDisplayNames: nil,
                modelPromptOverride: nil,
                attachmentContextBlock: nil,
                sources: nil,
                toolTrace: nil,
                feedbackRaw: nil,
                supersededReplyTexts: nil
            )
        ]
        let data = try! JSONEncoder().encode(original)
        let raw = String(data: data, encoding: .utf8)!
        UserDefaults.standard.set(raw, forKey: testStoreKey)

        let loadedRaw = UserDefaults.standard.string(forKey: testStoreKey)!
        let loaded = try! JSONDecoder().decode([PersistedAssistantMessage].self, from: Data(loadedRaw.utf8))
        #expect(loaded.count == 2)
        #expect(loaded[0].text == "What is my major?")
        #expect(loaded[1].text.contains("Computer Science"))
    }

    @Test("Message store round-trip restores full transcript")
    func messageStoreRoundTrip() {
        let testStoreKey = uniqueTestKey()
        defer { UserDefaults.standard.removeObject(forKey: testStoreKey) }
        let messages = [
            AssistantMessage(
                id: UUID(),
                isUser: true,
                role: .academicAdvisor,
                text: "Plan next semester",
                timestamp: Date()
            ),
            AssistantMessage(
                id: UUID(),
                isUser: false,
                role: .academicAdvisor,
                text: "Here is a draft plan.",
                timestamp: Date()
            )
        ]
        AssistantMessageStore.persist(messages, key: testStoreKey)
        let restored = AssistantMessageStore.load(key: testStoreKey)
        #expect(restored.count == 2)
        #expect(restored[0].text == "Plan next semester")
        #expect(restored[1].text.contains("draft plan"))
    }

    @Test("Message store caps at 120 items on persist")
    func messageStoreCapsAt120() {
        let testStoreKey = uniqueTestKey()
        defer { UserDefaults.standard.removeObject(forKey: testStoreKey) }
        let many = (0..<200).map { i in
            AssistantMessage(
                id: UUID(),
                isUser: i.isMultiple(of: 2),
                role: .academicAdvisor,
                text: "Message \(i)",
                timestamp: Date()
            )
        }
        AssistantMessageStore.persist(many, key: testStoreKey)
        let loaded = AssistantMessageStore.load(key: testStoreKey)
        #expect(loaded.count == 120)
        #expect(loaded.first?.text == "Message 80")
        #expect(loaded.last?.text == "Message 199")
    }

    @Test("Simulated session restore after clear and reload")
    func simulatedSessionRestore() {
        let testStoreKey = uniqueTestKey()
        defer { UserDefaults.standard.removeObject(forKey: testStoreKey) }
        let session = (0..<8).map { i in
            AssistantMessage(
                id: UUID(),
                isUser: i.isMultiple(of: 2),
                role: .academicAdvisor,
                text: "Turn \(i)",
                timestamp: Date()
            )
        }
        AssistantMessageStore.persist(session, key: testStoreKey)
        UserDefaults.standard.synchronize()
        let afterRestart = AssistantMessageStore.load(key: testStoreKey)
        #expect(afterRestart.count == 8)
        #expect(afterRestart.map(\.text) == session.map(\.text))
    }
}
