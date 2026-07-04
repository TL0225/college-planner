// AssistantRoutingEvalTests.swift
// Layer 2 — parameterized routing corpus (Swift Testing).

import Foundation
import Testing
@testable import College

@Suite("Assistant Routing Corpus")
struct AssistantRoutingEvalTests {

    @Test(arguments: RoutingCorpus.all)
    func routingIntentAndTool(case routingCase: RoutingCase) {
        let frame = AssistantIntentSemantics.intentFrame(
            message: routingCase.prompt,
            role: routingCase.assistantRole
        )
        guard let expectedIntent = routingCase.expectedIntent else { return }
        #expect(
            frame?.detectedIntent == expectedIntent,
            "Intent mismatch for \(routingCase.id): expected \(expectedIntent), got \(frame?.detectedIntent ?? "nil")"
        )
        if let expectedTool = routingCase.expectedTool {
            #expect(
                frame?.preferredTool == expectedTool,
                "Tool mismatch for \(routingCase.id): expected \(expectedTool), got \(frame?.preferredTool ?? "nil")"
            )
        }
    }

    @Test(arguments: RoutingCorpus.all)
    func routingProducesRouteDecision(case routingCase: RoutingCase) {
        _ = AIAssistantToolRouter.routeDecision(
            for: routingCase.prompt,
            role: routingCase.assistantRole,
            snapshot: AssistantTestFixtures.emptySnapshot,
            activePage: .assistant
        )
    }

    @Test("Routing corpus meets minimum size")
    func corpusSize() {
        #expect(RoutingCorpus.all.count >= 100)
    }

    @Test("Benchmark baseline accuracy")
    func routingBenchmarkBaseline() throws {
        let url = try TestFixturePaths.url("Assistant/routing-benchmark-baseline.json")
        let data = try Data(contentsOf: url)
        let baseline = try JSONDecoder().decode(RoutingBenchmarkBaseline.self, from: data)
        let result = RoutingBenchmarkEvaluator.evaluate(cases: RoutingCorpus.all)
        #expect(result.total >= baseline.minimumCaseCount)
        #expect(result.intentAccuracy >= baseline.minimumAccuracy)
        if let minimumToolAccuracy = baseline.minimumToolAccuracy {
            #expect(result.toolAccuracy >= minimumToolAccuracy)
        }
    }

    @Test("Benchmark drift vs recorded history")
    func routingBenchmarkDriftHistory() throws {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        var historyURL: URL?
        for _ in 0..<10 {
            let candidate = dir.appendingPathComponent("docs/assistant-benchmark-history.json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                historyURL = candidate
                break
            }
            dir = dir.deletingLastPathComponent()
        }
        guard let historyURL else { return }
        let history = try JSONDecoder().decode(BenchmarkHistoryFile.self, from: Data(contentsOf: historyURL))
        guard let latest = history.history.last else { return }
        let result = RoutingBenchmarkEvaluator.evaluate(cases: RoutingCorpus.all)
        let drift = latest.routingAccuracy - result.intentAccuracy
        #expect(
            drift <= 0.10,
            "Routing accuracy dropped \(String(format: "%.1f", drift * 100))% vs \(latest.month) history (\(latest.routingAccuracy))"
        )
    }
}

struct BenchmarkHistoryFile: Codable {
    struct Entry: Codable {
        let month: String
        let routingAccuracy: Double
        let caseCount: Int
    }
    let history: [Entry]
}

struct RoutingBenchmarkBaseline: Codable {
    let minimumAccuracy: Double
    let minimumToolAccuracy: Double?
    let minimumCaseCount: Int
    let recordedAt: String
    let notes: String?
}

enum RoutingBenchmarkEvaluator {
    struct Result {
        let total: Int
        let intentMatched: Int
        let toolMatched: Int
        let toolTotal: Int
        var intentAccuracy: Double { total > 0 ? Double(intentMatched) / Double(total) : 0 }
        var toolAccuracy: Double { toolTotal > 0 ? Double(toolMatched) / Double(toolTotal) : 0 }
    }

    static func evaluate(cases: [RoutingCase]) -> Result {
        var intentMatched = 0
        var total = 0
        var toolMatched = 0
        var toolTotal = 0
        for c in cases {
            guard let expectedIntent = c.expectedIntent else { continue }
            total += 1
            let frame = AssistantIntentSemantics.intentFrame(message: c.prompt, role: c.assistantRole)
            if frame?.detectedIntent == expectedIntent {
                intentMatched += 1
            }
            if let expectedTool = c.expectedTool {
                toolTotal += 1
                if frame?.preferredTool == expectedTool {
                    toolMatched += 1
                }
            }
        }
        return Result(
            total: total,
            intentMatched: intentMatched,
            toolMatched: toolMatched,
            toolTotal: toolTotal
        )
    }
}
