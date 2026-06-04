// AssistantContextAssembler.swift
// Feature: Assistant
// Purpose: Assistant module — Layer.
// Data: CollegePersistence / repositories when applicable.

import Foundation

/// Planner context layers with fixed priority truncation (`nonisolated` — no MainActor default).
enum AssistantContextAssembler: Sendable {
    struct Layer: Sendable {
        let priority: Int
        let label: String
        let text: String
    }

    nonisolated static func assemble(
        minimalProfile: AssistantMinimalProfileContext,
        plannerRAGBlock: String,
        webMemoryBlock: String,
        policyRAGBlock: String?,
        handbookBlock: String?,
        rollingSummaryBlock: String?,
        coldFallbackBlock: String?,
        budget: AssistantContextBudget,
        lengthPreset: String?
    ) -> String {
        let ceiling = budget.contextSummaryCeilingChars
        var layers: [Layer] = [
            Layer(priority: 1, label: "profile", text: minimalProfile.render(charBudget: budget.minimalProfileCharBudget)),
        ]
        if !plannerRAGBlock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            layers.append(Layer(priority: 2, label: "planner", text: plannerRAGBlock))
        }
        if !webMemoryBlock.isEmpty {
            layers.append(Layer(priority: 3, label: "web", text: webMemoryBlock))
        }
        if let policy = policyRAGBlock?.trimmingCharacters(in: .whitespacesAndNewlines), !policy.isEmpty {
            layers.append(Layer(priority: 4, label: "policy", text: policy))
        }
        if let handbook = handbookBlock?.trimmingCharacters(in: .whitespacesAndNewlines), !handbook.isEmpty {
            layers.append(Layer(priority: 5, label: "handbook", text: handbook))
        }
        if let rolling = rollingSummaryBlock?.trimmingCharacters(in: .whitespacesAndNewlines), !rolling.isEmpty {
            layers.append(Layer(priority: 5, label: "rolling", text: rolling))
        }
        if let cold = coldFallbackBlock?.trimmingCharacters(in: .whitespacesAndNewlines), !cold.isEmpty {
            layers.append(Layer(priority: 6, label: "fallback", text: cold))
        }

        layers.sort { $0.priority < $1.priority }
        var assembled = layers.map(\.text).joined(separator: "\n\n")
        guard assembled.count > ceiling else { return assembled }

        while assembled.count > ceiling, layers.count > 1 {
            guard let dropIdx = layers.indices.max(by: { layers[$0].priority < layers[$1].priority }) else { break }
            layers.remove(at: dropIdx)
            assembled = layers.map(\.text).joined(separator: "\n\n")
        }
        if assembled.count > ceiling {
            assembled = String(assembled.prefix(ceiling)) + "\n...(truncated)"
        }
        return assembled
    }

    nonisolated static func plannerRAGBlock(
        from hits: [PlannerVectorStore.ScoredRow],
        charBudget: Int
    ) -> String {
        guard !hits.isEmpty else { return "" }
        let header = "Planner context (on-device index):\n"
        var parts: [String] = []
        var used = header.utf8.count
        for hit in hits {
            let line = "- [\(hit.row.sourceType)] \(String(hit.row.ftsBody.prefix(280)))\n"
            if used + line.utf8.count > charBudget { break }
            parts.append(line)
            used += line.utf8.count
        }
        guard !parts.isEmpty else { return "" }
        return header + parts.joined()
    }

    nonisolated static func coldFallbackBlock(
        events: [String],
        tasks: [String],
        charBudget: Int
    ) -> String? {
        guard !events.isEmpty || !tasks.isEmpty else { return nil }
        var lines = ["Compressed planner fallback (index warming):"]
        for e in events.prefix(3) { lines.append("- Event: \(e)") }
        for t in tasks.prefix(3) { lines.append("- Task: \(t)") }
        var text = lines.joined(separator: "\n")
        if text.count > charBudget {
            text = String(text.prefix(charBudget))
        }
        return text
    }

    nonisolated static func shouldShowIndexingBanner(
        consentEnabled: Bool,
        chunkCount: Int,
        dismissedThisSession: Bool
    ) -> Bool {
        consentEnabled
            && chunkCount < PlannerVectorSearchConfig.usefulnessChunkFloor
            && !dismissedThisSession
    }
}
