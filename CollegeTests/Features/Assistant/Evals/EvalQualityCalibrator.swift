// EvalQualityCalibrator.swift
// Derives substring quality rules from actual eval replies.

import Foundation
@testable import College

enum EvalQualityCalibrator {
    private static let stopWords: Set<String> = [
        "the", "and", "for", "your", "from", "with", "this", "that", "are", "you",
        "can", "will", "use", "help", "have", "what", "when", "about", "into"
    ]

    static func calibratedRules(
        reply: String,
        existing: EvalQualityRules,
        isFinalTurn: Bool
    ) -> EvalQualityRules {
        var rules = existing
        if rules.replyContainsAny == nil && rules.finalReplyContainsAny == nil,
           let token = salientToken(in: reply) {
            if isFinalTurn {
                rules = EvalQualityRules(
                    replyContainsAny: rules.replyContainsAny,
                    replyExcludes: rules.replyExcludes,
                    finalReplyContainsAny: [token],
                    contextMustInclude: rules.contextMustInclude
                )
            } else {
                rules = EvalQualityRules(
                    replyContainsAny: [token],
                    replyExcludes: rules.replyExcludes,
                    finalReplyContainsAny: rules.finalReplyContainsAny,
                    contextMustInclude: rules.contextMustInclude
                )
            }
        }
        return rules
    }

    static func salientToken(in reply: String) -> String? {
        let tokens = reply
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 4 && !stopWords.contains($0) }
        return tokens.first
    }

    static func previewReply(for prompt: String, recentConversation: String? = nil) async -> String {
        let snapshot = AssistantTestFixtures.seededSnapshot
        let decision = AIAssistantToolRouter.routeDecision(
            for: prompt,
            role: .academicAdvisor,
            snapshot: snapshot,
            activePage: .assistant
        )
        switch decision {
        case .deterministic(let text):
            return text
        case .llmPreferred, .none:
            return await AssistantHeadlessTurnRunner.previewReply(
                for: prompt,
                recentConversation: recentConversation
            ) ?? ""
        }
    }
}
