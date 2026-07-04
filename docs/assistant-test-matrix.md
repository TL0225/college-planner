# Assistant Test Matrix

Behavior map: intent → tool → test file. Run smoke:

```bash
xcodebuild test -scheme College -destination 'platform=macOS' \
  -derivedDataPath /tmp/CollegeAssistantBuild \
  -only-testing:CollegeTests/AssistantRoutingEvalTests
```

## Layer 0 — Infrastructure

| Behavior | Pipeline | Test file |
|----------|----------|-----------|
| Prompt includes JSON schema + context | `AssistantPlanningPromptBuilder.makeActionPromptSegments` | `Infrastructure/AssistantPromptBuilderTests.swift` |
| Messages persist to UserDefaults | `AssistantMessageStore` + `PersistedAssistantMessage` | `Infrastructure/AssistantConversationPersistenceTests.swift` |
| Recent transcript window trim | `AssistantConversationSummaryBuilder.makeSummary` | `Infrastructure/AssistantConversationSummaryTests.swift` |
| Context assembly + budget trim | `AssistantContextAssembler.assemble` | `Infrastructure/AssistantContextAssemblyTests.swift` |

## Layer 1 — Chat UI (XCUITest)

| Behavior | Test file |
|----------|-----------|
| Open assistant, composer, session badge | `AssistantChatUITests.swift` |
| Send, multi-turn bubbles, empty send disabled | `AssistantChatUITests.swift` |
| Confirm/cancel, feedback toast | `AssistantInteractionUITests.swift` |
| Accessibility labels | `AssistantAccessibilityUITests.swift` |
| Auto-prompt eval recording | `AssistantEvalUITests.swift` |

## Layer 2 — Routing (Swift Testing)

| Student prompt | Intent | Tool | Corpus |
|----------------|--------|------|--------|
| What classes do I need to graduate? | `requirement_explanation` | `explainRequirements` | `routing-corpus.json` |
| Help me plan next semester | `next_semester_plan` | `draftSemesterPlan` | `routing-corpus.json` |
| What career does my major lead to? | `career_exploration` | `getStudentLearningProfile` | `routing-corpus.json` |
| Residency requirement | `degree_policy_lookup` | `semanticCatalogSearch` | `routing-corpus.json` |
| When is FAFSA due? | `fafsa_help` | `getAidDeadlines` | `routing-corpus.json` |

Benchmark: `Fixtures/Assistant/routing-benchmark-baseline.json` (≥95% intent on all 102 cases). Regenerate: run export tests, then `./scripts/copy-assistant-fixture-exports.sh` from repo root.

## Layer 3 — Tool logic

| Tool | Test file |
|------|-----------|
| Top 15 tools + registry | `Tools/AssistantToolExecutionTests.swift` |
| Post-M4 tools | `AssistantPostM4ToolsTests.swift` |
| Phase 8 registry | `AIAssistantPhase8ToolsTests.swift` |

## Layer 4 — Workflows

| Question | Expected chain | Test file |
|----------|----------------|-----------|
| Graduation risk | intent → `assessRequirementRisk` | `Workflows/AssistantWorkflowTests.swift` |
| Career + profile | `getStudentLearningProfile` | `Workflows/AssistantWorkflowTests.swift` |

## Layer 5 — AI evals

| Corpus | Count | Test file |
|--------|-------|-----------|
| Single-turn | 100 | `Evals/AssistantQualityEvalTests.swift` |
| Multi-turn | 20 | `Evals/AssistantQualityEvalTests.swift` |
| Comprehensive report | 7 scenarios | `AssistantComprehensiveEvaluationTests.swift` |

Headless runner: `College/Features/Assistant/AssistantHeadlessTurnRunner.swift`

## Layer 7 — Security

| Attack | Test file |
|--------|-----------|
| Protected settings, injection, escalation | `AssistantSecurityTests.swift` |

## Layer 8 — Performance

| Budget | Test file |
|--------|-----------|
| Router ≤800ms, intent ≤50ms | `Performance/AssistantLatencyTests.swift` |

## Layer 9 — Observability

| Check | Test file |
|-------|-----------|
| Telemetry, redaction, eval recorder | `Observability/AssistantObservabilityTests.swift` |

## Reliability

| Area | Test file |
|------|-----------|
| State machine, streaming, cancellation, offline | `Reliability/*.swift` |

## CI tiers

| Tier | Workflow | Scope |
|------|----------|-------|
| PR smoke | `assistant-tests.yml` | Layer 0 prompt + routing subset |
| Nightly | `assistant-tests.yml` (schedule) | Full routing + quality evals |

## Artifacts

- `docs/assistant-auto-prompt-log.json` — UI eval recording (intent, routePath, toolTrace)
- `docs/assistant-benchmark-history.json` — monthly routing accuracy
- `docs/assistant-evaluation-report.md` — comprehensive eval output
