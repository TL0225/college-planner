# College App — Performance Baseline Matrix (Phase 0)

**Status:** Release RSS sampled Jun 4 2026 (see recording below). XCTest budget gates green. Full Instruments POI pass optional for signpost wall times.  
**Budget source:** [`LaunchPerformanceAcceptance`](../College/Debug/LaunchPerformanceAcceptance.swift)  
**Signposts:** [`PerformanceSignposts`](../College/Core/PerformanceSignposts.swift) (`LoadAudit`, `CreditsProgressSummary`, `LLMLoad`, `LLMUnload`, `CatalogVectorReindex`)

**Phase 6 sign-off:** [`phase6-signoff-checklist.md`](phase6-signoff-checklist.md)  
**Architecture boundaries:** [`performance-architecture-signoff.md`](performance-architecture-signoff.md)

Record on **Release** builds on Apple Silicon unless noted. Use Allocations + Points of Interest in Instruments for signpost durations; `ps` RSS sampling is acceptable for launch steady-state checks.

---

## Scenario matrix

| Scenario | How to reproduce | Signpost / probe | Measured RSS (MB) | Measured wall time (ms) | Notes |
|----------|------------------|------------------|-------------------|-------------------------|-------|
| **Cold launch** | Release `College.app`; quit first; open; no Assistant tab | `LaunchPreloadCoordinator` / `ps rss` | **372** peak @10s; **315** @20s | — | Under Release warn **1200** MB |
| **Post-assistant idle** | Open Assistant once; send one message; wait ≥ idle timeout | `LLMUnload` after idle | — (Instruments) | — (Instruments) | Budget **1500** MB Release; sample after idle in Instruments |
| **Academics audit** | Degree tab; wait for audit spinner | `LoadAudit` | — (Instruments) | — (Instruments) | Budget **1600** MB peak; XCTest audit gate **3s** Release |
| **Vector reindex** | Full catalog vector rebuild | `CatalogVectorReindex` | — (Instruments) | — (Instruments) | Budget **2048** MB peak Release |
| **Background → foreground** | Background 2 min; return | Tab switch / stall telemetry | — (Instruments) | — (Instruments) | Budget **1400** MB steady Release |

---

## Wall-clock budgets

| Metric | Release warn | Debug warn | Helper |
|--------|-------------:|-----------:|--------|
| Launch preload pipeline | 45,000 ms | 120,000 ms | `pipelineDurationExceedsBudget(durationMs:)` |
| Academics `loadAudit` | 3,000 ms | 10,000 ms | `academicsAuditDurationExceedsBudget(durationMs:)` |

---

## Resident memory (RSS) budgets

Values are **warning** thresholds (investigate when exceeded). Tune after first baseline capture.

| Scenario | Release warn (MB) | Debug warn (MB) | Helper |
|----------|------------------:|----------------:|--------|
| Cold launch | 1,200 | 1,800 | `residentMemoryExceedsBudget(residentMB:scenario: .coldLaunch)` |
| Post-assistant idle | 1,500 | 2,500 | `.postAssistantIdle` |
| Academics audit (peak during load) | 1,600 | 2,600 | `.academicsAudit` |
| Vector reindex (peak) | 2,048 | 4,096 | `.vectorReindex` |
| Background → foreground (steady after resume) | 1,400 | 2,200 | `.backgroundForeground` |

---

## XCTest gates

| Test target | File |
|-------------|------|
| Launch pipeline | `CollegeTests/LaunchPerformanceAcceptanceTests.swift` |
| Phase 0 budgets | `CollegeTests/PerformanceBaselineAcceptanceTests.swift` |
| Calendar cache | `CollegeTests/CalendarCacheEnginePerfTests.swift` |
| LLM release | `CollegeTests/LocalLLMRunnerMemoryTests.swift` |

---

## Recording template (copy per run)

### Recorded — 2026-06-04 (Timothy, Mac14,2)

```
Date: 2026-06-04
Build: Release
Machine: Mac14,2 (Apple Silicon)
macOS: 26.5

Cold launch RSS: 372 MB peak (10s), 315 MB steady (20s)   pipeline ms: (Instruments POI optional)
Post-assistant idle RSS: —   (LLM unloaded: not measured this run)
Academics audit ms: —   peak RSS: —
Vector reindex ms: —   peak RSS: —
BG→FG stall events (>3s): —
```

Sampling command used:

```bash
open ~/Library/Developer/Xcode/DerivedData/College-*/Build/Products/Release/College.app
# then every 5s: ps -o rss= -p $(pgrep -x College)
```

### Instruments fill-in (manual — copy one row per run)

1. Product → **Profile** → **Release** `College.app`.
2. Template: **Allocations** + enable **Points of Interest** (`com.apple.college` / `Timothy.College`).
3. Reproduce one scenario from the matrix; note peak **Physical Memory** and POI duration for the signpost column.
4. Paste into the scenario row above and append a dated block under **Recording template**.

Example row after assistant-idle run:

| Post-assistant idle | (as matrix) | `LLMUnload` | **410** | **820** | Under 1500 MB budget |
