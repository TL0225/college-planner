# Resume Builder — Performance Baseline Ledger

**Status:** POST-EXECUTION (partial) — XCTest gates green; Instruments R1–R10 still manual.  
**Plan:** `.cursor/plans/resume_builder_overhaul_b2982a1b.plan.md`  
**Parent:** [`performance-baseline.md`](performance-baseline.md), [`instruments-baseline.md`](instruments-baseline.md)

Record on **Release** builds, Apple Silicon. Pair Instruments **Points of Interest** (`Timothy.College` subsystem) with RSS sampling.

---

## Pre-execution gate (required before Phase 0 code)

| Gate | Date | Build | Pass? | Notes |
| --- | --- | --- | --- | --- |
| G1 Clean build (`BuildProject` / xcodebuild) | 2026-07-03 | Debug | Pass | Isolated DerivedData `/tmp/CollegeDerivedData2` |
| G2 Resume test matrix (13 suites) | 2026-07-03 | Debug | Pass | ResumePipeline + Performance + Invariant + MatchEligibility + PageBudget |
| G3 Instruments R1–R10 below | | | | Manual Instruments session |
| G4 Navigator zero errors (Resume/Career) | 2026-07-03 | | Pass | IDE lints clean on Resume/Career |

---

## Instruments scenario matrix

| # | Scenario | Peak RSS (MB) | Hangs | POI ms | Notes |
| --- | --- | --- | --- | --- | --- |
| R1 Builder open (first PDF) | | | | `ResumeTypstCompile` (pre: none) | |
| R2 Builder field edit debounce | | | | | |
| R3 Section reorder DnD | | | | | Known broken pre-fix |
| R4 Save to library | | | | | |
| R5 Resume ingest (PDF import) | | | | | Same as instruments-baseline #8 |
| R6 Builder fast-path ingest | | | | N/A pre-overhaul | |
| R7 Job match score (3 resumes) | | | | | |
| R8 Apply autofill | | | | | |
| R9 DOCX export | | | | N/A pre-overhaul | |
| R10 Tailor save copy | | | | | |

### Pre-execution signoff

```
Date: 2026-07-03
Build: Debug
Machine: Apple Silicon (local)
macOS: 26.x
Reviewer: Agent

Pre ledger complete: [x] partial — build verification in progress; Instruments manual
```

---

## Post-execution comparison (after Phase 7)

Re-run identical scenarios. **Pass bar:** no scenario >20% regression vs pre column (or documented waiver in PR).

| # | Pre POI ms | Post POI ms | Δ% | Pre RSS | Post RSS | Pass? |
| --- | --- | --- | --- | --- | --- | --- |
| R1 | | | | | | |
| R2 | | | | | | |
| R3 | | | | | | |
| R4 | | | | | | |
| R5 | | | | | | |
| R6 | | | | | | |
| R7 | | | | | | |
| R8 | | | | | | |
| R9 | | | | | | |
| R10 | | | | | | |

---

## XCTest performance gates (Phase 5+)

| Test | Pre | Post | Budget |
| --- | --- | --- | --- |
| `ResumeBuilderPerformanceTests.testTypstCompileWithinBudget` | N/A | Pass (2026-07-03) | 800 ms Release |
| `testFastPathIngestSkipsLLM` | N/A | Pass | 500 ms |
| `testMatchCacheInvalidatesOnHashChange` | N/A | Pass | regression |
| `testDOCXExportNoForbiddenElements` | N/A | Pass | structural |
| `testBuilderReorderPersists` | N/A | Pass | behavioral |

---

## Test matrix reference (G2)

Run before and after via Xcode-tools `RunSomeTests` or:

```bash
xcodebuild -scheme College -destination 'platform=macOS' test \
  -only-testing:CollegeTests/ResumePipelineTests \
  -only-testing:CollegeTests/JobBoardMatchEligibilityTests \
  -only-testing:CollegeTests/JobBoardMatchServiceTests \
  -only-testing:CollegeTests/CareerResumeEligibilityTests \
  -only-testing:CollegeTests/CareerMatchCacheRevisionTests \
  -only-testing:CollegeTests/CareerResumeEditSessionTests \
  -only-testing:CollegeTests/CareerApplyPipelineTests \
  -only-testing:CollegeTests/CareerApplyCompletionTests \
  -only-testing:CollegeTests/JobBoardPipelineE2ETests \
  -only-testing:CollegeTests/JobBoardDetailTests \
  -only-testing:CollegeTests/CareerResumeStructuredParserTests \
  -only-testing:CollegeTests/CareerResumeTextExtractorTests \
  -only-testing:CollegeTests/PerformanceBaselineAcceptanceTests
```
