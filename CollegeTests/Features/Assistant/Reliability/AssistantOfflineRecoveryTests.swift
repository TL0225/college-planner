// AssistantOfflineRecoveryTests.swift
import Foundation
import Testing
@testable import College

@Suite("Assistant Offline Recovery")
struct AssistantOfflineRecoveryTests {

    @Test("Deterministic router works without network")
    @MainActor
    func deterministicRouterOffline() {
        let reply = AIAssistantToolRouter.reply(
            for: "what's my major",
            role: .academicAdvisor,
            snapshot: AssistantTestFixtures.csSnapshot,
            activePage: .academics
        )
        #expect(reply != nil)
        #expect(reply?.contains("Computer Science") == true)
    }

    @Test("Empty planner guided recovery copy")
    @MainActor
    func emptyPlannerGuidedRecovery() {
        let reply = AIAssistantToolRouter.reply(
            for: "what's due this week",
            role: .academicAdvisor,
            snapshot: AssistantTestFixtures.emptySnapshot,
            activePage: .calendar
        )
        #expect(reply != nil)
        #expect(!reply!.isEmpty)
    }

    @Test("Career without major guides instead of dumping")
    @MainActor
    func careerWithoutMajorGuided() {
        let decision = AIAssistantToolRouter.routeDecision(
            for: "What career does my major lead to?",
            role: .academicAdvisor,
            snapshot: AssistantTestFixtures.emptySnapshot,
            activePage: .assistant
        )
        if case .deterministic(let text) = decision {
            #expect(!text.contains("Current programs:"))
        }
    }
}
