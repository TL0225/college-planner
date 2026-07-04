// AssistantQualityEvalTests.swift
// Layer 5 — single-turn and multi-turn quality evals (Swift Testing).

import Foundation
import Testing
@testable import College

@Suite("Assistant Quality Evals")
struct AssistantQualityEvalTests {

    @Test(arguments: EvalCorpus.singleTurn)
    func singleTurnRoutingQuality(case evalCase: EvalCase) async {
        guard let prompt = evalCase.prompt else { return }
        let snapshot = AssistantTestFixtures.seededSnapshot
        let decision = AIAssistantToolRouter.routeDecision(
            for: prompt,
            role: .academicAdvisor,
            snapshot: snapshot,
            activePage: .assistant
        )
        let reply: String
        switch decision {
        case .deterministic(let text):
            reply = text
        case .llmPreferred:
            reply = await AssistantHeadlessTurnRunner.previewReply(for: prompt) ?? ""
        case .none:
            reply = await AssistantHeadlessTurnRunner.previewReply(for: prompt) ?? ""
        }
        let flags = EvalQualityChecker.flags(reply: reply, rules: evalCase.quality)
        #expect(flags.isEmpty, "Eval \(evalCase.id) quality flags: \(flags.joined(separator: ", "))")
    }

    @Test("Single-turn corpus size")
    func singleTurnCorpusSize() {
        #expect(EvalCorpus.singleTurn.count >= 100)
    }

    @Test("Multi-turn corpus size")
    func multiTurnCorpusSize() {
        #expect(EvalCorpus.multiTurn.count >= 20)
    }

    @Test(arguments: EvalCorpus.multiTurn)
    func multiTurnConversation(case evalCase: EvalCase) async {
        guard let turns = evalCase.turns, !turns.isEmpty else { return }
        var history: [String] = []
        var finalReply = ""
        for turn in turns {
            history.append("User: \(turn.user)")
            finalReply = await AssistantHeadlessTurnRunner.previewReply(
                for: turn.user,
                recentConversation: history.joined(separator: "\n")
            ) ?? finalReply
            history.append("Assistant: \(finalReply)")
        }
        let flags = EvalQualityChecker.flags(reply: finalReply, rules: evalCase.quality)
        #expect(!finalReply.isEmpty, "Eval \(evalCase.id) produced empty final reply")
        #expect(flags.isEmpty, "Eval \(evalCase.id) quality flags: \(flags.joined(separator: ", "))")
    }
}
