// AssistantGovernanceTests.swift
// Layer 2/5 boundary — governance, policy, telemetry (Swift Testing).

import Foundation
import Testing
@testable import College

@Suite("Assistant Governance")
struct AssistantGovernanceTests {

    @Test("Filter for synthesis drops general web for policy intent")
    func filterForSynthesisDropsGeneralWebForPolicyIntent() {
        let official = AssistantReplySource(
            title: "Registrar",
            url: "https://registrar.example.edu/policy",
            kind: .webSearch,
            toolName: "searxWebSearch",
            trustTier: .officialWeb
        )
        let general = AssistantReplySource(
            title: "Forum post",
            url: "https://reddit.com/r/college",
            kind: .webSearch,
            toolName: "searxWebSearch",
            trustTier: .webGeneral
        )
        let filtered = AssistantAcademicWebPolicy.filterForSynthesis(
            sources: [official, general],
            intent: "degree_policy_lookup",
            officialHosts: ["registrar.example.edu"]
        )
        #expect(filtered.count == 1)
        #expect(filtered.first?.title == "Registrar")
    }

    @Test("Filter passes through non-policy intent")
    func filterForSynthesisPassesThroughNonPolicyIntent() {
        let general = AssistantReplySource(
            title: "Blog",
            url: "https://example.com/blog",
            kind: .webSearch,
            toolName: "searxWebSearch",
            trustTier: .webGeneral
        )
        let filtered = AssistantAcademicWebPolicy.filterForSynthesis(
            sources: [general],
            intent: "career_exploration",
            officialHosts: []
        )
        #expect(filtered.count == 1)
    }

    @Test("Validate policy reply requires trusted source")
    func validatePolicyReplyRequiresTrustedSource() {
        let untrusted = AssistantReplySource(
            title: "Random",
            url: "https://example.com",
            kind: .webSearch,
            trustTier: .webGeneral
        )
        #expect(!AssistantAcademicWebPolicy.validatePolicyReply(
            sources: [untrusted],
            intent: "degree_policy_lookup"
        ))
        let catalog = AssistantReplySource(
            title: "Catalog",
            url: nil,
            kind: .webSearch,
            toolName: "semanticCatalogSearch",
            trustTier: .catalog
        )
        #expect(AssistantAcademicWebPolicy.validatePolicyReply(
            sources: [catalog],
            intent: "degree_policy_lookup"
        ))
    }

    @Test("Feedback cache key normalizes query")
    func feedbackGovernanceCacheKeyNormalizesQuery() {
        let key = AssistantFeedbackGovernance.cacheKey(
            query: "  What's My Major?  ",
            role: .academicAdvisor,
            universityName: "Example U"
        )
        #expect(key.contains("Academic Advisor"))
        #expect(key.contains("example u"))
        #expect(key.contains("what's my major?"))
    }

    @Test("Turn telemetry records path counters")
    func turnTelemetryRecordsPathCounters() {
#if DEBUG
        AssistantTurnTelemetry.resetForTesting()
        defer { AssistantTurnTelemetry.resetForTesting() }
        AssistantTurnTelemetry.record(
            AssistantTurnTelemetryRecord(
                intent: "career_exploration",
                path: .llmPreferred,
                latencyMS: 120,
                personalizationEligible: false,
                fallbackKind: nil,
                toolHopCount: 0,
                timestamp: Date()
            )
        )
        #expect(AssistantTurnTelemetry.counter("path.llmPreferred") == 1)
        #expect(AssistantTurnTelemetry.counter("intent.career_exploration") == 1)
#endif
    }

    @Test("Career exploration intent detected")
    func careerExplorationIntentDetected() {
        let frame = AssistantIntentSemantics.intentFrame(
            message: "What can I do with my computer science degree?",
            role: .academicAdvisor
        )
        #expect(frame?.detectedIntent == "career_exploration")
    }

    @Test("Web search tool context includes voice guide")
    func webSearchToolContextIncludesVoiceGuide() {
        let sources = [
            AssistantReplySource(
                title: "Registrar policy",
                url: "https://registrar.example.edu/pass-fail",
                kind: .webSearch,
                snippet: "Pass/fail limited to electives.",
                toolName: "searxWebSearch",
                trustTier: .officialWeb
            )
        ]
        let context = AssistantWebBypassSynthesis.toolContextBlock(
            webQuery: "pass fail policy",
            sources: sources,
            fetchContext: nil
        )
        #expect(context.contains("Registrar policy"))
        #expect(context.contains(AssistantVoiceGuide.academicAdvisorTone))
    }

    @Test("Should replay cached answer rejects untrusted policy cache")
    func shouldReplayCachedAnswerRejectsUntrustedPolicyCache() {
        let untrusted = AssistantReplySource(
            title: "Forum",
            url: "https://reddit.com",
            kind: .webSearch,
            trustTier: .webGeneral
        )
        #expect(!AssistantFeedbackGovernance.shouldReplayCachedAnswer(
            sources: [untrusted],
            intent: "degree_policy_lookup"
        ))
    }
}
