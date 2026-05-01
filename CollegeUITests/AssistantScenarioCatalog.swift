import Foundation

/// Single reference for scripted UI-test prompts and what they exercise.
///
/// **Tier1 — deterministic router** (no MLX; use `--uitest-fake-assistant-model` only):
/// - `tier1WeekAgenda`, `tier1DueItems`, `tier1Tomorrow`, `tier1ModelIdentity`, `tier1EventHelp`
///
/// **Tier2 — stub LLM** (`--uitest-local-llm-stub` + fake model; optional `--uitest-seed-minimal-planner`):
/// - `tier2ProgramProgress` — planning hop → `getProgramProgress` → final stub answer
/// - `tier2CreateTaskConfirm` — `createTask` confirmation card
///
/// **Tier3 — real Gemma**: same prompts without stub flags; manual / nightly only.
enum AssistantScenarioCatalog {
    static let tier1WeekAgenda = "What do I have this week?"
    static let tier1DueItems = "what is due"
    static let tier1Tomorrow = "What's on my calendar tomorrow?"
    static let tier1ModelIdentity = "what model are you"W
    static let tier1EventHelp = "create event for my study group"

    static let tier2ProgramProgress = "UITEST_STUB get program progress"
    static let tier2CreateTaskConfirm = "UITEST_CONFIRM create task"
}
