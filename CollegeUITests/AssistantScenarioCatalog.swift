import Foundation

/// Scripted prompts for `CollegeUITests/AssistantUITests.swift`.
///
/// **Harness flags** (see `CollegeUITestCase.applyAssistantHarness`):
/// - Fake model: `--uitest-fake-assistant-model` — chat shell without MLX weights
/// - Stub LLM: `--uitest-local-llm-stub` — deterministic planning/reply JSON
/// - Seed planner: `--uitest-seed-minimal-planner` — events, tasks, courses
/// - Declared major: `--uitest-seed-declared-major` — academic profile major
/// - Stub web: `--uitest-stub-web-search` — canned SearXNG + fetch results
enum AssistantScenarioCatalog {

    // MARK: - Tier 1 — deterministic router (fake model only)

    static let tier1WeekAgenda = "What do I have this week?"
    static let tier1DueItems = "what is due"
    static let tier1Tomorrow = "What's on my calendar tomorrow?"
    static let tier1ModelIdentity = "what model are you"
    static let tier1EventHelp = "create event for my study group"
    static let tier1SimpleMajor = "what's my major"
    static let tier1EmptyDueWindow = "what is due"

    // MARK: - Tier 1 — guided responses (human-guidance Ship A/B)

    static let guidedCareerWithoutMajor = "What career does my major lead to?"
    static let guidedSemesterBreakdown = "Can you create a semester-by-semester breakdown of my major?"
    static let guidedResidencyPolicy = "What's the residency requirement for my degree?"

    // MARK: - Tier 2 — stub LLM tool hops

    static let tier2ProgramProgress = "UITEST_STUB get program progress"
    static let tier2CreateTaskConfirm = "UITEST_CONFIRM create task"
    static let tier2CareerExploration = "What can I do with my computer science degree?"
    static let tier2PolicyLookup = "What's the residency requirement for my degree?"
    static let tier2SemesterBreakdown = "Can you create a semester-by-semester breakdown of my major?"

    // MARK: - Tier 2 — explicit web bypass + synthesis

    static let tier2ExplicitWebSearch = "search the web for UITEST residency policy"

    // MARK: - Regression guards

    static let regressionRoboticDumpProbe = "Can you create a semester by semester breakdown of my major?"
}
