# Resume Builder — Ship Signoff

**Status:** PARTIAL — automated gates filled; manual portal/VoiceOver/Instruments still open.  
**Plan:** `.cursor/plans/resume_builder_overhaul_b2982a1b.plan.md`  
**Related:** [`resume-builder-performance-baseline.md`](resume-builder-performance-baseline.md), [`manual-release-signoff.md`](manual-release-signoff.md)

---

## Build under test

```
Date: 2026-07-03
Release build: Pass — /tmp/CollegeDD-release-s1
Git SHA: 7f625fe (working tree has uncommitted resume overhaul)
Machine: Apple Silicon (local)
macOS: 26.5
Reviewer: Agent (automated gates) / human (manual gates)
```

---

## Automated gates (S1–S8)

| # | Gate | Pass? | Evidence |
| --- | --- | --- | --- |
| S1 | Release build zero errors | Pass | `BUILD SUCCEEDED` Release, DerivedData `/tmp/CollegeDD-release-s1` |
| S2 | Pre + post perf ledger; no >20% regression R1–R10 | Partial | XCTest perf gates pass; Instruments R1–R10 still manual (see performance-baseline.md) |
| S3 | 13-suite unit matrix + ResumeBuilderPerformanceTests | Pass | `ResumeBuilderPerformanceTests` + resume/job-board/apply smoke suites green locally |
| S4 | ResumePipelineInvariantTests | Pass | Includes cancel-mid-compile, draft restore, library link, canonical JSON credential scan |
| S5 | ResumeBuilderE2ETests + JobBoardApplyResumeE2ETests | Pass (logic) / Partial (UI) | `ResumeBuilderFlowTests` + invariants + apply session/E2E smoke `TEST SUCCEEDED`. UITests still need automation mode in Xcode/CI |
| S6 | career-jobboard-tests + career-apply-tests + college-tests-sharded CI | Pass (local smoke) | Job board + career apply smoke suites `TEST SUCCEEDED` (2026-07-03) |
| S7 | release-hardening.yml + app-ship-gates.yml | Pending | Requires push / GitHub Actions |
| S8 | scripts/check-feature-imports.sh fail | Pass | `check-feature-imports: no flagged cross-feature imports` |

---

## Manual gates (S9–S16)

| # | Gate | Pass? | Notes |
| --- | --- | --- | --- |
| S9 | Workday apply with builder PDF | | URL: |
| S10 | Greenhouse apply with builder PDF | | URL: |
| S11 | Lever apply (or manual upload documented) | | URL: |
| S12 | DOCX export → ATS upload test | | Portal: |
| S13 | Re-save resume → match % updates | | |
| S14 | Tailor → apply path end-to-end | | |
| S15 | VoiceOver builder wizard complete | Partial | AX IDs/labels on builder root, title, advanced toggle, categories, save, attachment sheet, Home ribbon, platform variants — human VoiceOver walkthrough still open |
| S16 | Security review (temp files, no log leaks) | Pass (code review) | See security notes below |

### S16 security notes (code review)

- Apply temp PDFs deleted on `CareerApplySessionStore.close` and on `rebuildPayload` (stale URL removed first).
- Apply window `onDisappear` now always `store.close` so traffic-light close cannot leak temp PDFs.
- No `print`/`NSLog` in Resume or CareerApply sources for payload/canonical JSON.
- `testCanonicalJSONHasNoCredentialFields` asserts resume canonical encoding has no password/SSN/API-key fields.
- `closeCleansTempAndIsIdempotent` covers double-close after window teardown.

---

## Known limitations (documented to users)

- [x] ATS portal compatibility varies; export sheet states this
- [x] PDF vs DOCX preview may differ slightly
- [x] Image-only/scanned PDFs may parse poorly
- [x] Some portals require manual file attach gesture

---

## Final signoff

```
All S1–S16 checked: [ ]
Approved to ship: [ ]
Waivers (if any):
  - S2 Instruments R1–R10: waive to XCTest perf gates until human Instruments session
  - S5 UITests: re-run when automation mode available
  - S7 CI workflows: confirm on push

Signature / date:
```
