// AssistantConversationSummaryTests.swift
// Layer 0 — recent conversation window trimming (Swift Testing).

import Foundation
import Testing
@testable import College

@Suite("Assistant Conversation Summary")
struct AssistantConversationSummaryTests {

    @Test("Recent conversation summary trims to budget window")
    func recentConversationSummaryTrims() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let messages = (0..<200).map { i in
            AssistantMessage(
                id: UUID(),
                isUser: i.isMultiple(of: 2),
                role: .academicAdvisor,
                text: "Message \(i)",
                timestamp: base.addingTimeInterval(TimeInterval(i))
            )
        }
        let budget = AssistantContextBudget.forLengthPreset("balanced")
        let summary = AssistantConversationSummaryBuilder.makeSummary(
            messages: messages,
            currentPrompt: "Latest question",
            recentMessageCount: budget.recentMessageCount
        )
        #expect(!summary.contains("Message 0"))
        #expect(!summary.contains("Message 100"))
        #expect(summary.contains("Message 199"))
        #expect(summary.contains("[Now] User: Latest question"))
    }

    @Test("Empty transcript returns placeholder")
    func emptyTranscriptPlaceholder() {
        let summary = AssistantConversationSummaryBuilder.makeSummary(
            messages: [],
            currentPrompt: "Hello",
            recentMessageCount: 10
        )
        #expect(summary == "No earlier conversation in this session.")
    }

    @Test("Long message text is truncated in summary")
    func longMessageTruncated() {
        let longText = String(repeating: "x", count: 400)
        let messages = [
            AssistantMessage(
                id: UUID(),
                isUser: true,
                role: .academicAdvisor,
                text: longText,
                timestamp: Date()
            )
        ]
        let summary = AssistantConversationSummaryBuilder.makeSummary(
            messages: messages,
            currentPrompt: "Follow up",
            recentMessageCount: 5
        )
        #expect(summary.contains("..."))
        #expect(summary.count < longText.count + 80)
    }
}
