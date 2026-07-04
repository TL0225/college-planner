# PDF Corpus Re-run — 2026-06-16

Comparison after catalog architecture audit (P0–P31) vs locked P0 baseline in `golden_samples.json` and vs pre-audit requirement snapshot (Jun 16 ~01:00).

## Courses & programs (frozen P0 baseline — exact match)

| Catalog | Courses (baseline → now) | Programs (baseline → now) | Delta |
|---|---|---|---|
| Fordham | 7721 → **7721** | 295 → **295** | 0 |
| CMU Undergrad | 3757 → **3757** | 55 → **55** | 0 |
| Brooklyn Undergrad | 2871 → **2871** | 177 → **177** | 0 |
| Brooklyn Grad | 1899 → **1899** | 68 → **68** | 0 |

All four still pass exact course/program count assertions. No regression on the primary extraction outputs.

## Requirements (vs pre-audit locked snapshot)

| Catalog | Before audit | Now | Δ groups | Programs w/ reqs (before → now) |
|---|---|---|---|---|
| Fordham | 720 | **729** | **+9** | 138 → **140** |
| CMU Undergrad | 298 | **155** | **−143** | 36 → 36 |
| Brooklyn Undergrad | 175 | **180** | **+5** | 125 → **127** |
| Brooklyn Grad | 57 | **59** | **+2** | 43 → **44** |

## Program coverage (% of extracted programs with ≥1 requirement group)

| Catalog | Before (approx) | Now |
|---|---|---|
| Fordham | ~57% | ~57% |
| CMU Undergrad | ~65% | ~65% |
| Brooklyn Undergrad | ~93% | ~93% |
| Brooklyn Grad | ~64% | ~65% |

## Gold-standard requirement P/R/F1 (seed labels in `catalog_gold_standard.json`)

Seed set is small (1–2 programs per school); use as directional signal only.

Corpus regression: Fordham, Brooklyn UG, Brooklyn Grad **pass**. CMU Undergrad **fails** `minRequirementGroups` floor (155 < 220).

## What improved

1. **Fordham** — +9 requirement groups, +2 programs with requirements; course/program parity held.
2. **Brooklyn Undergrad** — +5 requirement groups, +2 programs with requirements; still ~93% program coverage.
3. **Brooklyn Grad** — +2 requirement groups, +1 program with requirements.
4. **Cross-cutting** — Layout IR (reading order + column detection), header/footer stripping on requirement lines (P6), and table IR augmentation did not break frozen course/program counts on any catalog.

## What regressed

1. **CMU Undergrad requirements** — dropped from 298 → **155** groups (−48%), breaching the corpus floor of 220. Courses/programs unchanged (3757 / 55). Likely interaction between layout IR line reordering and CMU unit-table requirement paths — needs targeted fix before claiming CMU parity.

## Historical context (Jun 14 debug harness — pre-requirement work)

Early broken state for reference: CMU had 926 courses / 2 programs / 0 requirements; Brooklyn UG had 3 courses / 0 programs. Current pipeline is dramatically better than that snapshot; this comparison is against the Jun 16 locked baseline, not Jun 14.

## Test commands used

```bash
xcodebuild test -scheme College -destination 'platform=macOS' \
  -only-testing:CollegeTests/CatalogPDFSampleHarnessTests/testAuditDumpsFullScraperOutput

xcodebuild test -scheme College -destination 'platform=macOS' \
  -only-testing:CollegeTests/CatalogPDFCorpusFixtureTests/testCorpusFordham
# (+ Brooklyn UG/Grad pass; CMU fails minRequirementGroups)
```
