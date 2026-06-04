// AssistantIntentEmbeddingClassifier.swift
// Feature: Assistant
// Purpose: Assistant module — AssistantIntentPrototype.
// Data: CollegePersistence / repositories when applicable.

import Foundation

// MARK: - Settings

enum AssistantIntentEmbeddingSettings {
    static let enabledKey = "assistant.intent.embedding.enabled"
    static let thresholdKey = "assistant.intent.embedding.threshold"
    static let marginKey = "assistant.intent.embedding.margin"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) != nil
            ? UserDefaults.standard.bool(forKey: enabledKey)
            : true
    }

    /// Cosine similarity threshold for lexical prototype embeddings (tune per field feedback).
    static var similarityThreshold: Float {
        if UserDefaults.standard.object(forKey: thresholdKey) != nil {
            return Float(UserDefaults.standard.double(forKey: thresholdKey))
        }
        return 0.78
    }

    /// Minimum gap between best and second-best intent scores to avoid ambiguous routing.
    static var minimumIntentMargin: Float {
        if UserDefaults.standard.object(forKey: marginKey) != nil {
            return Float(UserDefaults.standard.double(forKey: marginKey))
        }
        return 0.04
    }
}

// MARK: - Prototypes

struct AssistantIntentPrototype: Sendable {
    let intentId: String
    let phrases: [String]
}

private enum AssistantIntentPrototypes {
    static let all: [AssistantIntentPrototype] = [
        .init(intentId: "web_search", phrases: [
            "search the web", "look that up online", "google this", "find on the internet",
            "search online for", "can you search for", "web search for"
        ]),
        .init(intentId: "first_semester_plan", phrases: [
            "plan my first semester", "what classes should I take as a freshman",
            "freshman schedule", "first term courses", "starting college classes",
            "new student schedule", "what should I take first semester"
        ]),
        .init(intentId: "next_semester_plan", phrases: [
            "plan my next semester", "what should I take next term",
            "next semester classes", "upcoming semester plan", "schedule for next term"
        ]),
        .init(intentId: "multi_semester_plan", phrases: [
            "two semester plan", "graduation plan", "course sequence", "multi semester",
            "sequence my courses", "whole degree plan", "map out my degree"
        ]),
        .init(intentId: "requirement_explanation", phrases: [
            "what do I still need to graduate", "degree requirements left",
            "requirement check", "what is left for my degree", "audit my progress"
        ]),
        .init(intentId: "registration_readiness", phrases: [
            "am I ready to register", "registration blockers", "what could stop registration",
            "holds before I register", "can I register for classes"
        ]),
        .init(intentId: "weekly_schedule", phrases: [
            "study schedule", "weekly schedule", "plan my week around classes",
            "balance work and school schedule", "time blocks for studying"
        ]),
        .init(intentId: "event_action", phrases: [
            "add a calendar event", "create an event", "schedule a meeting",
            "put on my calendar", "new calendar event"
        ]),
        .init(intentId: "fafsa_help", phrases: [
            "how do I apply for FAFSA", "fafsa deadline", "fafsa verification",
            "dependency status fafsa", "fsa id help", "student aid application"
        ]),
        .init(intentId: "state_aid_help", phrases: [
            "state grant eligibility", "TAP scholarship", "cal grant requirements",
            "state financial aid", "HESC aid", "bright futures scholarship"
        ]),
        .init(intentId: "sap_risk", phrases: [
            "satisfactory academic progress", "SAP financial aid", "will withdrawing hurt SAP",
            "completion rate SAP", "gpa requirement for aid"
        ]),
        .init(intentId: "enrollment_intensity", phrases: [
            "am I full time for aid", "credits for full time", "dropping below 12 credits",
            "part time vs full time aid", "enrollment intensity"
        ]),
        .init(intentId: "aid_estimate", phrases: [
            "how much aid will I get", "estimate my pell grant", "rough aid package",
            "how much money for college", "expected family contribution help"
        ]),
        .init(intentId: "award_letter_review", phrases: [
            "review my award letter", "compare aid offer", "explain my financial aid offer",
            "uploaded aid document", "award letter numbers"
        ]),
        .init(intentId: "financial_aid", phrases: [
            "financial aid question", "help with paying for college",
            "tuition assistance options", "student aid office question"
        ])
    ]
}

// MARK: - Classifier

enum AssistantIntentEmbeddingClassifier {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cachedRows: [(intentId: String, vector: [Float])]?

    /// Best intent by max prototype cosine similarity per intent, with margin guard between top two intents.
    static func classify(message: String, threshold: Float, minimumIntentMargin: Float) -> (intentId: String, confidence: Float)? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let userVec = AssistantWebMemoryEmbedding.vector(for: trimmed)
        guard userVec.count == AssistantWebMemoryEmbedding.dimension else { return nil }

        var bestPerIntent: [String: Float] = [:]
        for row in prototypeVectorRows() {
            let s = AssistantWebMemoryEmbedding.cosineSimilarity(userVec, row.vector)
            let prev = bestPerIntent[row.intentId] ?? -1
            if s > prev { bestPerIntent[row.intentId] = s }
        }
        guard !bestPerIntent.isEmpty else { return nil }
        let ranked = bestPerIntent.sorted { $0.value > $1.value }
        guard let top = ranked.first, top.value >= threshold else { return nil }
        if ranked.count >= 2, top.value - ranked[1].value < minimumIntentMargin {
            return nil
        }
        return (top.key, top.value)
    }

    static func warmUp() {
        _ = prototypeVectorRows()
    }

    private static func prototypeVectorRows() -> [(intentId: String, vector: [Float])] {
        lock.lock()
        defer { lock.unlock() }
        if let cachedRows { return cachedRows }
        var rows: [(intentId: String, vector: [Float])] = []
        for proto in AssistantIntentPrototypes.all {
            for phrase in proto.phrases {
                let v = AssistantWebMemoryEmbedding.vector(for: phrase)
                if v.count == AssistantWebMemoryEmbedding.dimension {
                    rows.append((proto.intentId, v))
                }
            }
        }
        cachedRows = rows
        return rows
    }
}
