// AssistantContextBudget.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantContextBudget.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Caps for assistant context packaging, tied to `assistant.response.lengthPreset` in Settings.
struct AssistantContextBudget: Sendable {
    let recentMessageCount: Int
    let queryMemoryCharBudget: Int
    let recentMemoryCharBudget: Int
    let queryMemoryMaxRows: Int
    let recentMemoryMaxRows: Int
    let planMaxTokens: Int
    let replyMaxTokens: Int
    let helpfulMemoryCharBudget: Int
    let maxTextPerFile: Int
    let maxTotalContext: Int
    let maxRenderedPDFPages: Int
    let ocrMaxChars: Int

    static let lengthPresetKey = "assistant.response.lengthPreset"

    static func forLengthPreset(_ raw: String?) -> AssistantContextBudget {
        switch raw ?? "balanced" {
        case "short":
            return AssistantContextBudget(
                recentMessageCount: 6,
                queryMemoryCharBudget: 720,
                recentMemoryCharBudget: 960,
                queryMemoryMaxRows: 8,
                recentMemoryMaxRows: 12,
                planMaxTokens: 260,
                replyMaxTokens: 400,
                helpfulMemoryCharBudget: 900,
                maxTextPerFile: 12_000,
                maxTotalContext: 24_000,
                maxRenderedPDFPages: 2,
                ocrMaxChars: 6_000
            )
        case "detailed":
            return AssistantContextBudget(
                recentMessageCount: 16,
                queryMemoryCharBudget: 2200,
                recentMemoryCharBudget: 2800,
                queryMemoryMaxRows: 12,
                recentMemoryMaxRows: 18,
                planMaxTokens: 380,
                replyMaxTokens: 600,
                helpfulMemoryCharBudget: 1600,
                maxTextPerFile: 20_000,
                maxTotalContext: 42_000,
                maxRenderedPDFPages: 4,
                ocrMaxChars: 10_000
            )
        default:
            return AssistantContextBudget(
                recentMessageCount: 10,
                queryMemoryCharBudget: 1200,
                recentMemoryCharBudget: 1600,
                queryMemoryMaxRows: 10,
                recentMemoryMaxRows: 14,
                planMaxTokens: 320,
                replyMaxTokens: 480,
                helpfulMemoryCharBudget: 1200,
                maxTextPerFile: 15_000,
                maxTotalContext: 30_000,
                maxRenderedPDFPages: 3,
                ocrMaxChars: 8_000
            )
        }
    }

    static func currentFromUserDefaults() -> AssistantContextBudget {
        forLengthPreset(UserDefaults.standard.string(forKey: lengthPresetKey))
    }

    var contextSummaryCeilingChars: Int { max(1200, maxTotalContext / 4) }
    var minimalProfileCharBudget: Int { min(900, helpfulMemoryCharBudget) }

    /// Combined character budget for web-memory blocks (query + recent + helpful) in planner context.
    var maxCombinedWebMemoryChars: Int {
        let sum = queryMemoryCharBudget + recentMemoryCharBudget + helpfulMemoryCharBudget
        return min(sum, max(2000, maxTotalContext / 5))
    }
}
