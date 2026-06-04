# Phase 6 — Performance verification sign-off

Manual checklist after code changes land. Budget constants live in [`LaunchPerformanceAcceptance`](../College/Debug/LaunchPerformanceAcceptance.swift); recorded baselines in [`performance-baseline.md`](performance-baseline.md).

## Automated gates (CI)

```bash
./scripts/run-performance-gates.sh          # Debug: full CollegeTests (287)
./scripts/run-performance-gates.sh Release  # Release: perf + schema + mmap subset
```

Or manually:

```bash
./scripts/check-neutral-persistence-labels.sh
./scripts/check-no-vision-llm.sh
./scripts/check-no-gemma4.sh
xcodebuild test -scheme College -destination 'platform=macOS' -only-testing:CollegeTests -jobs 1
```

| Gate | Target |
|------|--------|
| `LaunchPerformanceAcceptanceTests` | Pipeline budgets + generous RSS gates |
| `PerformanceBaselineAcceptanceTests` | Audit duration + per-scenario RSS thresholds |
| `SchemaMigrationPlanTests` | V1 schema identifier + in-memory containers |

## Settings diagnostics (runtime)

1. **Settings → Privacy & Security → Performance Diagnostics** — expand “Runtime snapshot”
   - Resident memory updates while expanded
   - JSON worker loaded / installed state
   - local store summary + active catalog path
   - Last memory pressure (after simulating warning — see Instruments note below)

2. **Settings → Assistant → Runtime diagnostics** card
   - Same RSS / LLM / catalog path / memory-pressure fields refresh every ~2s

## Instruments (Release, Apple Silicon)

1. **Allocations + Points of Interest** — template from `performance-baseline.md` scenario matrix
2. **Cold launch** — no Assistant tab; confirm RSS below cold-launch warn threshold
3. **Academics audit** — `LoadAudit` signpost completes within release budget (3s)
4. **Post-assistant idle** — `LLMUnload` fires after idle timeout; RSS drops toward pre-LLM baseline
5. **Memory pressure (optional)** — Debug → Simulate Memory Warning; Settings shows `memoryPressure.warning` timestamp

## Sign-off

- [x] CI gates green on macOS (Debug: 290 run / 0 fail / 10 skip; Release perf subset re-verified post-reorg)
- [x] Settings diagnostics show plausible values on a dev machine
- [x] Release RSS recorded in `performance-baseline.md` (372 MB peak cold launch; under 1200 MB budget)
- [x] Architecture doc (`docs/ARCHITECTURE.md`) — feature-first tree, Core/Data, naming conventions
- [x] Feature-first test layout (`CollegeTests/Features/`, `CollegeTests/Persistence/`)
- [x] Performance manifest refreshed (`docs/performance-file-manifest-index.tsv`, 626 paths)
- [x] Full `CollegeTests` re-run after reorg (`./scripts/run-performance-gates.sh` — 290 run, 10 skip, 0 fail)
- [ ] Optional: full Instruments Allocations + POI pass — fill signpost ms + peak RSS for assistant idle, audit, reindex, BG→FG rows in `performance-baseline.md`
- [x] No duplicate catalog mmap at launch (`LaunchSingleCatalogMmapTests`)
