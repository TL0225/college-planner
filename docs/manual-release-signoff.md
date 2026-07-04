# Manual release signoff

Checklist before tagging a release or merging the App Ship Refinement program. Automated Tier A gates run in [`.github/workflows/app-ship-gates.yml`](../.github/workflows/app-ship-gates.yml).

## Automated gates (CI — must be green)

- [ ] `app-ship-gates.yml` — static guards (dead code, Core Data, skipped tests, platform boundary)
- [ ] `app-ship-gates.yml` — Release build
- [ ] `app-ship-gates.yml` — package tests (`CollegeCalendar`, `CollegeAcademics`, `CollegeCareer`)
- [ ] `app-ship-gates.yml` — `./scripts/run-performance-gates.sh Release`
- [ ] `app-ship-gates.yml` — `./scripts/run_toolbar_tests.sh`
- [ ] `app-ship-gates.yml` — `./scripts/run_catalog_tests.sh`
- [ ] `app-ship-gates.yml` — `python3 scripts/test_compare_catalog_exports.py`
- [ ] `release-hardening.yml` — entitlements + hardened runtime
- [ ] `toolbar-architecture.yml` — forbidden symbols + toolbar XCTest suite
- [ ] `catalog-tests.yml` — catalog offline suite

Local equivalents:

```bash
bash scripts/check-target-membership.sh
bash scripts/check-dead-code-manifest.sh
bash scripts/check-blocking-patterns.sh
bash scripts/check-skipped-tests.sh
bash scripts/check-no-coredata.sh
bash scripts/run-performance-gates.sh Release
bash scripts/run_toolbar_tests.sh
bash scripts/run_catalog_tests.sh
python3 scripts/test_compare_catalog_exports.py
for pkg in CollegeCalendar CollegeAcademics CollegeCareer; do (cd "Packages/$pkg" && swift test); done
```

## Compile integrity

- [ ] Career workspace routes compile (`CareerWorkspaceCompileSmokeTests`)
- [ ] No missing flat-vs-subfolder Career duplicates in target membership
- [ ] Swift 6 strict-concurrency warnings triaged for Release target

## Performance & Instruments

- [ ] Pre-fix baseline captured in [`instruments-baseline.md`](instruments-baseline.md)
- [ ] Post-fix matrix re-run; no regressions vs pre-fix without waiver
- [ ] RSS samples updated in [`performance-baseline.md`](performance-baseline.md)
- [ ] Optional full Allocations + POI pass for assistant idle, audit, reindex, BG→FG

## UI / HIG smoke (manual)

- [ ] 10× tab cycle: Calendar → Academics → Career → Documents → Overview — toolbar swaps correctly
- [ ] Settings opens via native standalone window (not in-window route)
- [ ] Reduce Motion: no infinite shimmer; restrained tab transitions
- [ ] Career: job detail, resume library, application tracker load without layout glitches

## Data & persistence

- [ ] Schema migration tests pass (`SchemaMigrationPlanTests`)
- [ ] Fresh install and upgrade-from-V1 smoke on dev machine
- [ ] No Phase 7f store mirrors reintroduced (`ProfilePlannerStoreMirror`, `VaultStoreMirror`, `JobBoardStoreMirror`)

## Documentation freshness

- [ ] [`performance-file-manifest.md`](performance-file-manifest.md) header matches current `College/` Swift file count
- [ ] [`reorg-orphans.md`](reorg-orphans.md) reflects deleted paths (no stale “pending delete” entries)
- [ ] Toolbar ADRs and [`toolbar-ship-gate-signoff.md`](toolbar-ship-gate-signoff.md) still accurate

## TestFlight beta (production readiness)

- [ ] TestFlight build uploaded and distributed to beta group
- [ ] ≥2 weeks of crash-free sessions >99.5% (MetricKit / crash reports)
- [ ] No P0 regressions on job board sync, launch, or Academics audit from beta feedback

## Signoff

| Role | Name | Date | Notes |
|------|------|------|-------|
| Engineering | | | |
| QA / reviewer | | | |
