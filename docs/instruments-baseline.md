# Instruments baseline — pre-fix scenario checklist

Manual signoff template recorded **before** App Ship Refinement edits land. Use Release builds on Apple Silicon unless noted. Pair with [`performance-baseline.md`](performance-baseline.md) for RSS budgets and [`phase6-signoff-checklist.md`](phase6-signoff-checklist.md) for automated gates.

## Instruments templates

| Template | Purpose |
|----------|---------|
| **Time Profiler** | Main-thread stalls, hot symbols during tab switches and ingest |
| **Hangs** | UI unresponsiveness >250 ms |
| **Allocations + Leaks** | Peak resident memory, leak growth across tab cycles |
| **Points of Interest** | Signpost wall times (`com.apple.college` / `Timothy.College`) |
| **Swift Concurrency** | Actor hops, task priority inversion |
| **Main Thread Checker** | Blocking I/O or sync on UI thread |
| **Energy Log** | MLX / Metal contention during Assistant or catalog embed |

## Scenario matrix (record before fixes)

Reproduce each scenario once; paste peak RSS, hang count, and POI duration into the signoff block at the bottom.

| # | Scenario | How to reproduce | Instruments focus | Peak RSS (MB) | Hangs | POI / notes |
|---|----------|------------------|-------------------|---------------|-------|-------------|
| 1 | **Cold launch** | Quit app; open Release build; stay on Overview (no Assistant) | Allocations + POI | | | Launch preload pipeline |
| 2 | **Tab switch** | Cycle Calendar → Academics → Career → Documents → Overview 10× | Time Profiler + Hangs | | | Toolbar swap latency |
| 3 | **Assistant + PDF** | Open Assistant; attach a resume PDF; send one prompt | Allocations + Energy | | | `LLMLoad` / attachment ingest |
| 4 | **Career job detail + ATS** | Job Board → open posting → wait for match/ATS panel | Time Profiler + Main Thread | | | ATS scoring on detail pane |
| 5 | **Vault file open** | Documents → open encrypted PDF from vault | Allocations + Main Thread | | | Decrypt + materialize path |
| 6 | **Catalog sync / reindex** | Settings → trigger catalog sync or full vector reindex | Allocations + Energy | | | `CatalogVectorReindex` |
| 7 | **Brightspace / web load** | Open Brightspace tab; navigate one course page | Time Profiler + Allocations | | | WebKit + coordinator init |
| 8 | **Resume ingest** | Career → Resumes → import PDF; wait for parse/compliance | Time Profiler + POI | | | PDFKit / OCR fallback |

## Pre-fix signoff block (copy per run)

```
Date:
Build: Release
Machine: (e.g. Mac14,2)
macOS:

| Scenario | Peak RSS | Hangs | POI ms / notes | Pass pre-fix bar? |
|----------|----------|-------|----------------|-------------------|
| Cold launch | | | | |
| Tab switch | | | | |
| Assistant + PDF | | | | |
| Career ATS | | | | |
| Vault open | | | | |
| Catalog reindex | | | | |
| Brightspace | | | | |
| Resume ingest | | | | |

Reviewer:
```

## Acceptance after Wave 4–6

Re-run the same matrix after runtime offload and UI/HIG work. Compare against this pre-fix ledger; regressions require a waiver in the release signoff ([`manual-release-signoff.md`](manual-release-signoff.md)).
