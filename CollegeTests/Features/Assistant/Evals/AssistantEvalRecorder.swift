// AssistantEvalRecorder.swift
// Layer 5 — eval artifact recorder for CI and weak-spot review.

import Foundation
@testable import College

enum AssistantEvalRecorder {

    struct Record: Codable, Sendable {
        let id: String
        let prompt: String
        let intent: String?
        let routePath: String
        let reply: String
        let flags: [String]
        let latencyMS: Int?
        let toolTrace: [String]?
    }

    struct Report: Codable, Sendable {
        let generatedAt: String
        let records: [Record]
        let flaggedCount: Int
    }

    @MainActor
    static func evaluatePrompt(
        _ prompt: String,
        snapshot: AssistantPlannerSnapshot = AssistantTestFixtures.seededSnapshot
    ) async -> Record {
        let clock = ContinuousClock()
        let start = clock.now
        let intent = AssistantIntentSemantics.classify(message: prompt, role: .academicAdvisor)?.matchedIntent
        let decision = AIAssistantToolRouter.routeDecision(
            for: prompt,
            role: .academicAdvisor,
            snapshot: snapshot,
            activePage: .assistant
        )
        let routePath: String
        let reply: String
        switch decision {
        case .deterministic(let text):
            routePath = "deterministic"
            reply = text
        case .llmPreferred:
            routePath = "llmPreferred"
            reply = await AssistantHeadlessTurnRunner.previewReply(for: prompt) ?? ""
        case .none:
            routePath = "planner"
            reply = await AssistantHeadlessTurnRunner.previewReply(for: prompt) ?? ""
        }
        let elapsed = Int((clock.now - start).components.seconds * 1000)
        var flags: [String] = []
        if reply.contains("Current programs:\n- Majors:") { flags.append("robotic_program_dump") }
        if reply.isEmpty { flags.append("empty_reply") }
        return Record(
            id: UUID().uuidString,
            prompt: prompt,
            intent: intent,
            routePath: routePath,
            reply: reply,
            flags: flags,
            latencyMS: elapsed,
            toolTrace: nil
        )
    }

    static func writeMarkdownReport(records: [Record], to url: URL) throws {
        var lines = [
            "# Assistant Eval Report",
            "",
            "Generated: \(ISO8601DateFormatter().string(from: Date()))",
            "",
            "Flagged: \(records.filter { !$0.flags.isEmpty }.count) / \(records.count)",
            ""
        ]
        for record in records {
            lines.append("## \(record.prompt.prefix(80))")
            lines.append("")
            lines.append("- Intent: `\(record.intent ?? "—")`")
            lines.append("- Route: `\(record.routePath)`")
            lines.append("- Latency: \(record.latencyMS.map(String.init) ?? "—") ms")
            if !record.flags.isEmpty {
                lines.append("- Flags: \(record.flags.joined(separator: ", "))")
            }
            lines.append("")
            lines.append("```")
            lines.append(record.reply)
            lines.append("```")
            lines.append("")
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
