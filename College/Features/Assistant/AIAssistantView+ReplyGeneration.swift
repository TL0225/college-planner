// AIAssistantView+ReplyGeneration.swift
// Feature: Assistant
// Purpose: Model reply + tool-loop generation (Phase 6 decomposition).

import SwiftUI
import Foundation

extension AIAssistantView {
    @MainActor
    func makeAssistantToolExecutionContext(
        persona: AssistantPersona,
        snapshot: AssistantPlannerSnapshot,
        activeIntent: String?,
        programIdentity: AssistantProgramIdentityContext
    ) -> AssistantToolExecutionContext {
        var context = AssistantToolExecutionContext(
            collegePersistence: collegePersistence,
            activePage: activePage,
            selectedPersona: persona,
            snapshot: snapshot,
            currentDate: Date(),
            activeIntent: activeIntent,
            programIdentity: programIdentity
        )
        context.navigate = { page in AskCollegeCoordinator.navigateToPage(page) }
        context.openSettings = { section in AskCollegeCoordinator.openSettingsSection(section) }
        return context
    }

    @MainActor
    func generateReply(
        for prompt: String,
        role: AssistantAgentRole,
        hadAttachments: Bool,
        ingest: AssistantAttachmentIngestor.Result,
        onRawChunk: (@Sendable (String) async -> Void)? = nil
    ) async throws -> AssistantTurnResult {
        let turnStart = Date()
        try Task.checkCancellation()
        setAssistantBreadcrumb("generateReply.snapshot.begin")
        let snapshot = plannerSnapshotForTurn()
        setAssistantBreadcrumb("generateReply.snapshot.end")
        let serviceRole: AIAssistantService.Role = role == .academicAdvisor ? .academicAdvisor : .financialAid
        let persona: AssistantPersona = role == .academicAdvisor ? .academicAdvisor : .financialAdvisor
        let recentConversation = makeRecentConversationSummary(currentPrompt: prompt)
        let classifiedIntent = AssistantIntentSemantics.classify(message: prompt, role: serviceRole)?.matchedIntent
        AssistantSessionContinuity.recordTurn(intent: classifiedIntent, userQuery: prompt)

        let attachmentBlock = ingest.contextBlock.trimmingCharacters(in: .whitespacesAndNewlines)
        let routerSeesAttachments = hadAttachments || !attachmentBlock.isEmpty

        let decision = AIAssistantToolRouter.routeDecision(
            for: prompt,
            role: serviceRole,
            snapshot: snapshot,
            activePage: activePage,
            hasAttachments: routerSeesAttachments
        )

        func finish(_ result: AssistantTurnResult, path: AssistantTurnPath, hops: Int = 0, personalization: Bool? = nil, fallback: String? = nil) -> AssistantTurnResult {
            let ms = max(0, Int(Date().timeIntervalSince(turnStart) * 1000))
            AssistantTurnTelemetry.record(
                AssistantTurnTelemetryRecord(
                    intent: classifiedIntent,
                    path: path,
                    latencyMS: ms,
                    personalizationEligible: personalization,
                    fallbackKind: fallback,
                    toolHopCount: hops,
                    timestamp: Date()
                )
            )
            return result
        }

        switch decision {
        case .deterministic(let deterministicReply):
            setAssistantBreadcrumb("generateReply.router.deterministic")
            let fallback: String? = deterministicReply.contains("Current programs:") ? "raw_program_dump" : nil
            return finish(AssistantTurnResult(text: deterministicReply, sources: []), path: .guided, fallback: fallback)
        case .llmPreferred(let seed):
            setAssistantBreadcrumb("generateReply.router.llmPreferred")
            var contextSummary = await makeAssistantContextSummary(from: snapshot, userPrompt: prompt)
            if let seed, !seed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                contextSummary += "\n\nDeterministic planner seed:\n\(seed)\n\nUse this seed as grounding context, but provide a personalized explanation and recommendations instead of repeating the template verbatim."
            }
            return finish(try await generateToolAwareReply(
                for: prompt,
                serviceRole: serviceRole,
                persona: persona,
                snapshot: snapshot,
                contextSummary: contextSummary,
                recentConversation: recentConversation,
                attachmentContextBlock: attachmentBlock.isEmpty ? nil : attachmentBlock,
                deterministicSeed: seed,
                activeIntent: classifiedIntent,
                onRawChunk: onRawChunk
            ), path: .llmPreferred)
        case .none:
            setAssistantBreadcrumb("generateReply.router.miss")
            if AssistantIntentSemantics.isEnabled,
               let suggestion = AssistantIntentSemantics.classify(message: prompt, role: serviceRole),
               suggestion.confidence >= 0.7 {
                logAssistant("Semantic route hit intent=\(suggestion.matchedIntent) confidence=\(suggestion.confidence)")
                switch suggestion.decision {
                case .deterministic(let text):
                    return finish(AssistantTurnResult(text: text, sources: []), path: .guided)
                case .llmPreferred(let seed):
                    var semanticContext = await makeAssistantContextSummary(from: snapshot, userPrompt: prompt)
                    if let seed, !seed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        semanticContext += "\n\nSemantic seed:\n\(seed)"
                    }
                    return finish(try await generateToolAwareReply(
                        for: prompt,
                        serviceRole: serviceRole,
                        persona: persona,
                        snapshot: snapshot,
                        contextSummary: semanticContext,
                        recentConversation: recentConversation,
                        attachmentContextBlock: attachmentBlock.isEmpty ? nil : attachmentBlock,
                        deterministicSeed: seed,
                        activeIntent: suggestion.matchedIntent,
                        onRawChunk: onRawChunk
                    ), path: .llmPreferred)
                case .none:
                    break
                }
            }
        }

        let contextSummary = await makeAssistantContextSummary(from: snapshot, userPrompt: prompt)
        return finish(try await generateToolAwareReply(
            for: prompt,
            serviceRole: serviceRole,
            persona: persona,
            snapshot: snapshot,
            contextSummary: contextSummary,
            recentConversation: recentConversation,
            attachmentContextBlock: attachmentBlock.isEmpty ? nil : attachmentBlock,
            activeIntent: classifiedIntent,
            onRawChunk: onRawChunk
        ), path: .toolLoop)
    }

    @MainActor
    func generateToolAwareReply(
        for prompt: String,
        serviceRole: AIAssistantService.Role,
        persona: AssistantPersona,
        snapshot: AssistantPlannerSnapshot,
        contextSummary: String,
        recentConversation: String,
        attachmentContextBlock: String?,
        deterministicSeed: String? = nil,
        activeIntent: String? = nil,
        onRawChunk: (@Sendable (String) async -> Void)? = nil
    ) async throws -> AssistantTurnResult {
        let programIdentity = AssistantProgramIdentityBuilder.build(persistence: collegePersistence)
        let planningCatalogJSON = AIAssistantToolRegistry.planningCatalogJSON(for: persona)
        let planningToolNames = AIAssistantToolRegistry.planningToolNames(for: persona)
        let policyContext = makeAssistantPolicyContext(for: prompt)
        let fullRagContext = await makeAssistantPolicyRAGContext(for: prompt, serviceRole: serviceRole, policyContext: policyContext)
        let slimRagContext: String? = {
            guard let text = fullRagContext?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            if text.count <= 500 { return text }
            return String(text.prefix(500)) + "\n...(truncated for planning)"
        }()
        var planningToolContext: String? = slimRagContext
        var toolExecutionRecords: [String: AssistantToolCallDedupeRecord] = [:]
        var accumulatedSources: [AssistantReplySource] = []
        var accumulatedToolTrace: [AssistantToolTraceEntry] = []
        let executor = AIAssistantToolExecutor(
            context: makeAssistantToolExecutionContext(
                persona: persona,
                snapshot: snapshot,
                activeIntent: activeIntent,
                programIdentity: programIdentity
            )
        )
        let officialHosts = AssistantAcademicWebPolicy.officialHosts(
            persistence: collegePersistence,
            programIdentity: programIdentity
        )
        let maxToolHops: Int = {
            if activeIntent == "career_exploration" {
                return min(2, dynamicMaxToolHops)
            }
            return dynamicMaxToolHops
        }()

        // Hard bypass: explicit web-search prompts should not depend on model planning.
        // This guarantees web lookup still works even when local planning/generation fails.
        if let webQuery = explicitWebSearchQuery(from: prompt) {
            let universityName = collegePersistence.getActiveUniversityName()
            let cacheKey = acceptedWebAnswerCacheKey(query: webQuery, role: selectedRole, universityName: universityName)
            if let cached = try? await AssistantWebMemoryStore.shared.lookupAcceptedWebAnswer(cacheKey: cacheKey, maxAgeDays: 14) {
                let cachedSources = decodeSavedSources(json: cached.sourcesJSON)
                if AssistantFeedbackGovernance.shouldReplayCachedAnswer(sources: cachedSources, intent: activeIntent) {
                    return AssistantTurnResult(
                        text: """
Saved answer (from prior thumbs-up):
\(cached.answer)
""",
                        sources: cachedSources
                    )
                }
            }
            let directSearchStart = Date()
            let directSearch = await executor.execute(
                call: AssistantToolCallEnvelope(
                    tool: "searxWebSearch",
                    arguments: [
                        "query": .string(webQuery),
                        "maxResults": .number(6)
                    ]
                )
            )
            let directSearchLatencyMS = max(0, Int(Date().timeIntervalSince(directSearchStart) * 1000.0))
            let directSearchTrace = AssistantToolTraceEntry(
                toolName: "searxWebSearch",
                hopIndex: 0,
                latencyMS: directSearchLatencyMS,
                ok: directSearch.ok,
                summary: toolTraceSummary(from: directSearch)
            )

            if directSearch.ok {
                var webSources = AssistantToolSources.extract(
                    from: directSearch,
                    toolName: "searxWebSearch",
                    hopIndex: 0,
                    latencyMS: directSearchLatencyMS
                )
                webSources = annotateSourceTrust(webSources, officialHosts: officialHosts)
                webSources = AssistantAcademicWebPolicy.filterForSynthesis(
                    sources: webSources,
                    intent: activeIntent,
                    officialHosts: officialHosts
                )
                if !webSources.isEmpty {
                    var toolTrace = [directSearchTrace]
                    var fetchContext: String?
                    if let officialURL = webSources.compactMap(\.url).first(where: { urlStr in
                        guard let host = URL(string: urlStr)?.host?.lowercased() else { return false }
                        return officialHosts.contains(host)
                    }) {
                        let fetchStart = Date()
                        let fetchResult = await executor.execute(
                            call: AssistantToolCallEnvelope(
                                tool: "fetchWebPageReadable",
                                arguments: ["url": .string(officialURL)]
                            )
                        )
                        let fetchLatencyMS = max(0, Int(Date().timeIntervalSince(fetchStart) * 1000.0))
                        toolTrace.append(
                            AssistantToolTraceEntry(
                                toolName: "fetchWebPageReadable",
                                hopIndex: 1,
                                latencyMS: fetchLatencyMS,
                                ok: fetchResult.ok,
                                summary: toolTraceSummary(from: fetchResult)
                            )
                        )
                        if fetchResult.ok {
                            fetchContext = makeToolContext(from: fetchResult)
                            webSources = annotateSourceTrust(
                                AssistantToolSources.mergeUnique(
                                    webSources,
                                    AssistantToolSources.extract(
                                        from: fetchResult,
                                        toolName: "fetchWebPageReadable",
                                        hopIndex: 1,
                                        latencyMS: fetchLatencyMS
                                    )
                                ),
                                officialHosts: officialHosts
                            )
                        }
                    }

                    let synthesized = await synthesizeWebBypassReply(
                        webQuery: webQuery,
                        sources: webSources,
                        fetchContext: fetchContext,
                        serviceRole: serviceRole,
                        contextSummary: contextSummary,
                        recentConversation: recentConversation,
                        attachmentContextBlock: attachmentContextBlock,
                        policyContext: policyContext,
                        onRawChunk: onRawChunk
                    )
                    return finalizeAssistantTurn(
                        text: synthesized,
                        sources: webSources,
                        toolTrace: toolTrace,
                        activeIntent: activeIntent,
                        officialHosts: officialHosts,
                        programIdentity: programIdentity,
                        snapshot: snapshot
                    )
                }
            }

            let searchFailureSummary = directSearch.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            let searchFailureText = searchFailureSummary.isEmpty ? "Direct web search failed." : searchFailureSummary
            return AssistantTurnResult(
                text: """
I tried a direct web search for "\(webQuery)", but it failed:
\(searchFailureText)

Check Assistant web-search settings and try again.
""",
                sources: [],
                toolTrace: [directSearchTrace]
            )
        }

        assistantToolHop: for hop in 0..<maxToolHops {
            try Task.checkCancellation()
            if hop > 0 {
                await Task.yield()
                try await Task.sleep(nanoseconds: Self.toolHopPlanDebounceNs)
                try Task.checkCancellation()
            }
            let planning = await AIAssistantService.shared.planResponse(
                message: prompt,
                role: serviceRole,
                contextSummary: contextSummary,
                recentConversation: recentConversation,
                toolCatalogJSON: planningCatalogJSON,
                allowedPlanningToolNames: planningToolNames,
                planningToolContext: planningToolContext,
                attachmentContextBlock: attachmentContextBlock,
                policyContext: policyContext
            )

            if let fallbackReply = planning.fallbackReply {
                if let reason = planning.failureReason {
                    setAssistantBreadcrumb("generateReply.plan.failure.\(reason.rawValue)")
                }
                if let seed = deterministicSeed?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !seed.isEmpty,
                   planning.failureReason != nil {
                    let combined = """
\(seed)

---

\(fallbackReply)
"""
                    return finalizeAssistantTurn(
                        text: combined,
                        sources: accumulatedSources,
                        toolTrace: accumulatedToolTrace,
                        activeIntent: activeIntent,
                        officialHosts: officialHosts,
                        programIdentity: programIdentity,
                        snapshot: snapshot
                    )
                }
                return finalizeAssistantTurn(
                    text: fallbackReply,
                    sources: accumulatedSources,
                    toolTrace: accumulatedToolTrace,
                    activeIntent: activeIntent,
                    officialHosts: officialHosts,
                    programIdentity: programIdentity,
                    snapshot: snapshot
                )
            }

            guard let action = planning.action else {
                setAssistantBreadcrumb("generateReply.plan.empty")
                let replyContext = replyContextMergingFullRAG(contextSummary: contextSummary, fullRagContext: fullRagContext)
                let outcome = await AIAssistantService.shared.generateReplyOutcome(
                    message: prompt,
                    role: serviceRole,
                    contextSummary: replyContext,
                    recentConversation: recentConversation,
                    toolContext: planningToolContext,
                    attachmentContextBlock: attachmentContextBlock,
                    policyContext: policyContext,
                    onRawChunk: onRawChunk
                )
                try Task.checkCancellation()
                return finalizeAssistantTurn(
                    text: outcome.reply,
                    sources: accumulatedSources,
                    toolTrace: accumulatedToolTrace,
                    activeIntent: activeIntent,
                    officialHosts: officialHosts,
                    programIdentity: programIdentity,
                    snapshot: snapshot
                )
            }

            switch action {
            case .finalAnswer(let reply):
                setAssistantBreadcrumb("generateReply.plan.direct.hop\(hop)")
                return finalizeAssistantTurn(
                    text: reply,
                    sources: accumulatedSources,
                    toolTrace: accumulatedToolTrace,
                    activeIntent: activeIntent,
                    officialHosts: officialHosts,
                    programIdentity: programIdentity,
                    snapshot: snapshot
                )
            case .toolCall(let call):
                setAssistantBreadcrumb("generateReply.plan.tool.\(call.tool).hop\(hop)")
                viewModel.activeAssistantToolName = call.tool
                if let descriptor = AIAssistantToolRegistry.descriptor(named: call.tool),
                   descriptor.requiresConfirmation {
                    if let pending = pendingAction(from: call) {
                        pendingAction = pending
                        return AssistantTurnResult(
                            text: "I drafted that action. Review the confirmation card below and choose Confirm or Cancel.",
                            sources: accumulatedSources,
                            toolTrace: accumulatedToolTrace
                        )
                    }
                    return AssistantTurnResult(
                        text: "I understood that you want to make a change, but the action details were incomplete. Please include the title and timing details.",
                        sources: accumulatedSources,
                        toolTrace: accumulatedToolTrace
                    )
                }
                let signature = Self.canonicalToolCallSignature(for: call)
                if let existing = toolExecutionRecords[signature] {
                    if existing.lastOk {
                        logAssistant("Breaking tool loop: duplicate successful call to \(call.tool)", level: .info)
                        break assistantToolHop
                    }
                    if existing.consumedFailedRetry {
                        logAssistant("Breaking tool loop: duplicate call after failed retry for \(call.tool)", level: .info)
                        break assistantToolHop
                    }
                }
                let toolStart = Date()
                let toolResult = await executor.execute(call: call)
                let ok = toolResult.ok
                if var existing = toolExecutionRecords[signature] {
                    if !existing.lastOk && !existing.consumedFailedRetry {
                        existing.consumedFailedRetry = true
                        existing.lastOk = ok
                        toolExecutionRecords[signature] = existing
                    } else {
                        toolExecutionRecords[signature] = AssistantToolCallDedupeRecord(
                            lastOk: ok,
                            consumedFailedRetry: existing.consumedFailedRetry
                        )
                    }
                } else {
                    toolExecutionRecords[signature] = AssistantToolCallDedupeRecord(lastOk: ok, consumedFailedRetry: false)
                }
                let toolLatencyMS = max(0, Int(Date().timeIntervalSince(toolStart) * 1000.0))
                accumulatedToolTrace.append(
                    AssistantToolTraceEntry(
                        toolName: call.tool,
                        hopIndex: hop,
                        latencyMS: toolLatencyMS,
                        ok: toolResult.ok,
                        summary: toolTraceSummary(from: toolResult)
                    )
                )
                accumulatedSources = annotateSourceTrust(
                    AssistantToolSources.mergeUnique(
                        accumulatedSources,
                        AssistantToolSources.extract(
                            from: toolResult,
                            toolName: call.tool,
                            hopIndex: hop,
                            latencyMS: toolLatencyMS
                        )
                    ),
                    officialHosts: officialHosts
                )
                let piece = makeToolContext(from: toolResult)
                if let existing = planningToolContext, !existing.isEmpty {
                    planningToolContext = existing + "\n\n---\n\n" + piece
                } else {
                    planningToolContext = piece
                }
            }
        }

        setAssistantBreadcrumb("generateReply.plan.maxHops")
        let replyContextMaxHops = replyContextMergingFullRAG(contextSummary: contextSummary, fullRagContext: fullRagContext)
        let outcome = await AIAssistantService.shared.generateReplyOutcome(
            message: prompt,
            role: serviceRole,
            contextSummary: replyContextMaxHops,
            recentConversation: recentConversation,
            toolContext: planningToolContext,
            attachmentContextBlock: attachmentContextBlock,
            policyContext: policyContext,
            onRawChunk: onRawChunk
        )
        if let reason = outcome.failureReason {
            setAssistantBreadcrumb("generateReply.service.failure.\(reason.rawValue)")
        }
        try Task.checkCancellation()
        if let seed = deterministicSeed?.trimmingCharacters(in: .whitespacesAndNewlines),
           !seed.isEmpty,
           outcome.failureReason != nil {
            let combined = """
\(seed)

---

\(outcome.reply)
"""
            return finalizeAssistantTurn(
                text: combined,
                sources: accumulatedSources,
                toolTrace: accumulatedToolTrace,
                activeIntent: activeIntent,
                officialHosts: officialHosts,
                programIdentity: programIdentity,
                snapshot: snapshot
            )
        }
        return finalizeAssistantTurn(
            text: outcome.reply,
            sources: accumulatedSources,
            toolTrace: accumulatedToolTrace,
            activeIntent: activeIntent,
            officialHosts: officialHosts,
            programIdentity: programIdentity,
            snapshot: snapshot
        )
    }

    private func synthesizeWebBypassReply(
        webQuery: String,
        sources: [AssistantReplySource],
        fetchContext: String?,
        serviceRole: AIAssistantService.Role,
        contextSummary: String,
        recentConversation: String,
        attachmentContextBlock: String?,
        policyContext: AssistantPolicyContext?,
        onRawChunk: (@Sendable (String) async -> Void)?
    ) async -> String {
        let toolContext = AssistantWebBypassSynthesis.toolContextBlock(
            webQuery: webQuery,
            sources: sources,
            fetchContext: fetchContext
        )
        let outcome = await AIAssistantService.shared.generateReplyOutcome(
            message: webQuery,
            role: serviceRole,
            contextSummary: contextSummary,
            recentConversation: recentConversation,
            toolContext: toolContext,
            attachmentContextBlock: attachmentContextBlock,
            policyContext: policyContext,
            onRawChunk: onRawChunk
        )
        let reply = outcome.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if !reply.isEmpty, outcome.failureReason == nil {
            return reply
        }
        return AssistantWebBypassSynthesis.linkListFallback(webQuery: webQuery, sources: sources)
    }

    private func finalizeAssistantTurn(
        text: String,
        sources: [AssistantReplySource],
        toolTrace: [AssistantToolTraceEntry],
        activeIntent: String?,
        officialHosts: Set<String>,
        programIdentity: AssistantProgramIdentityContext,
        snapshot: AssistantPlannerSnapshot
    ) -> AssistantTurnResult {
        let annotated = annotateSourceTrust(sources, officialHosts: officialHosts)
        let filtered = AssistantAcademicWebPolicy.filterForSynthesis(
            sources: annotated,
            intent: activeIntent,
            officialHosts: officialHosts
        )
        if activeIntent == "degree_policy_lookup",
           !AssistantAcademicWebPolicy.validatePolicyReply(sources: filtered, intent: activeIntent) {
            let catalogURL = programIdentity.programURL ?? collegePersistence.activeSchoolPolicyMetadata()?.catalogURL
            return AssistantTurnResult(
                text: AssistantGuidedResponse.text(for: .missingOfficialSource, snapshot: snapshot, catalogURL: catalogURL),
                sources: filtered,
                toolTrace: toolTrace
            )
        }
        return AssistantTurnResult(text: text, sources: filtered, toolTrace: toolTrace)
    }

    private func annotateSourceTrust(
        _ sources: [AssistantReplySource],
        officialHosts: Set<String>
    ) -> [AssistantReplySource] {
        sources.map { source in
            let tier = source.trustTier ?? AssistantAcademicWebPolicy.trustTier(for: source, officialHosts: officialHosts)
            return AssistantReplySource(
                title: source.title,
                url: source.url,
                kind: source.kind,
                snippet: source.snippet,
                toolName: source.toolName,
                hopIndex: source.hopIndex,
                latencyMS: source.latencyMS,
                trustTier: tier
            )
        }
    }
}
