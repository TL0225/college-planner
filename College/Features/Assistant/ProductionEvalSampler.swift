// ProductionEvalSampler.swift
// Layer 6 — production eval pipeline stub (opt-in sampling + promotion hooks).

import Foundation

#if DEBUG
enum ProductionEvalSampler {

    struct SampledTurn: Codable, Sendable {
        let anonymizedPromptHash: String
        let intent: String?
        let routePath: String
        let flagged: Bool
        let timestamp: String
    }

    struct PromotionCandidate: Codable, Sendable {
        let prompt: String
        let reason: String
        let source: String
    }

    private static let queueKey = "assistant.productionEval.queue.v1"

    static func recordSample(prompt: String, intent: String?, routePath: String, flagged: Bool) {
        let hash = String(prompt.hashValue)
        let sample = SampledTurn(
            anonymizedPromptHash: hash,
            intent: intent,
            routePath: routePath,
            flagged: flagged,
            timestamp: ISO8601DateFormatter().string(from: Date())
        )
        var queue = loadQueue()
        queue.append(sample)
        if queue.count > 500 { queue.removeFirst(queue.count - 500) }
        saveQueue(queue)
    }

    static func promotionCandidates(limit: Int = 20) -> [PromotionCandidate] {
        loadQueue()
            .filter(\.flagged)
            .suffix(limit)
            .map { sample in
                PromotionCandidate(
                    prompt: "[hash:\(sample.anonymizedPromptHash)]",
                    reason: "flagged_production_sample",
                    source: "ProductionEvalSampler"
                )
            }
    }

    private static func loadQueue() -> [SampledTurn] {
        guard let data = UserDefaults.standard.data(forKey: queueKey),
              let decoded = try? JSONDecoder().decode([SampledTurn].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func saveQueue(_ queue: [SampledTurn]) {
        guard let data = try? JSONEncoder().encode(queue) else { return }
        UserDefaults.standard.set(data, forKey: queueKey)
    }

    static func resetForTesting() {
        UserDefaults.standard.removeObject(forKey: queueKey)
    }
}
#endif
