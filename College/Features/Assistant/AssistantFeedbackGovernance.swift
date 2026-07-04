// AssistantFeedbackGovernance.swift
// Feature: Assistant
// Purpose: Thumbs-down cache/snippet invalidation (Ship B).

import Foundation

enum AssistantFeedbackGovernance {
    static func recordHelpful(
        query: String,
        reply: String,
        role: AssistantAgentRole,
        universityName: String?,
        sources: [AssistantReplySource]
    ) {
        AssistantConversationMemory.recordHelpful(userQuery: query, assistantReply: reply)
        guard !sources.isEmpty else { return }
        let hasTrusted = sources.contains { src in
            switch src.trustTier {
            case .planner, .catalog, .officialWeb:
                return true
            default:
                return false
            }
        }
        guard hasTrusted else { return }
        let sourceStrings = sources.compactMap { src -> [String: String]? in
            guard let url = src.url else { return nil }
            return ["title": src.title, "url": url]
        }
        guard let sourceData = try? JSONEncoder().encode(sourceStrings),
              let sourceJSON = String(data: sourceData, encoding: .utf8) else { return }
        let key = cacheKey(query: query, role: role, universityName: universityName)
        Task {
            try? await AssistantWebMemoryStore.shared.saveAcceptedWebAnswer(
                cacheKey: key,
                query: query,
                role: role.rawValue,
                universityName: universityName,
                answer: reply,
                sourcesJSON: sourceJSON
            )
        }
    }

    static func recordNotHelpful(
        query: String,
        role: AssistantAgentRole,
        universityName: String?
    ) {
        let key = cacheKey(query: query, role: role, universityName: universityName)
        Task {
            try? await AssistantWebMemoryStore.shared.deleteAcceptedWebAnswer(cacheKey: key)
        }
        AssistantConversationMemory.removeHelpfulMatching(query: query)
    }

    /// Policy-shaped cached answers replay only when at least one trusted source tier is present.
    static func shouldReplayCachedAnswer(
        sources: [AssistantReplySource],
        intent: String?
    ) -> Bool {
        guard intent == "degree_policy_lookup" else { return true }
        return sources.contains { src in
            switch src.trustTier {
            case .planner, .catalog, .officialWeb:
                return true
            default:
                return false
            }
        }
    }

    static func cacheKey(query: String, role: AssistantAgentRole, universityName: String?) -> String {
        let uni = universityName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(role.rawValue)|\(uni)|\(normalized)"
    }
}
