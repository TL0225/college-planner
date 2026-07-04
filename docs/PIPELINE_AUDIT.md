# Career Openings — Pipeline Audit

Living reference for the nine-stage Openings pipeline: expected behavior, invariants, and test coverage.

## Pipeline map

```
Config (UserDefaults) → SyncCoordinator → Scraper → Import (SwiftData)
  → ReadBridge → List UI → Detail scrape → Resume ingest → ATS match → Tracker/Apply
```

| Stage | Primary files | Persistence |
|-------|---------------|-------------|
| 1 Config | `JobBoardCompanyPickerSheet`, `JobBoardCompaniesStore`, `JobBoardPlatformDetector` | UserDefaults `workday.companies.v1` |
| 2 Sync | `JobBoardSyncCoordinator`, `JobBoardRefreshScheduler` | UserDefaults sync timestamps |
| 3 Scrape | `JobBoardScraperRegistry`, platform scrapers | — |
| 4 Import | `CareerRepository+JobBoardImport` | `WorkdayJobPosting` |
| 5 Read/UI | `JobBoardReadBridge`, `JobBoardCompanyJobsView` | — |
| 6 Detail | `JobBoardJobDetailPane`, `applyJobBoardDetail` | JD + `descriptionHash` |
| 7 Resume | `CareerResumeIngestService`, `CareerResumeMetadataV1` | Vault JSON metadata |
| 8 Match | `JobBoardMatchEligibility`, `CareerATSService`, `CareerResumeJobMatch` | Match cache rows |
| 9 Tracker | `promoteJobBoardPostingToTracker`, `CareerApplyLauncher` | `JobApplication` links |

## Invariant checklist

### Stage 1 — Config
- [x] Platform detection matches URL host patterns (`JobBoardConfigTests`)
- [ ] HTTPS careers URLs only
- [ ] Duplicate slug/URL returns existing company (no double-add)

### Stage 2 — Sync
- [x] `minScrapeCooldown` is 30s (`JobBoardSyncTests`)
- [ ] One in-flight scrape per company slug
- [ ] Progress UI caps at 99% until import completes

### Stage 4 — Import
- [x] Upsert key: `(companySlug, externalPath)`
- [x] Unchanged `listingHash` → only `lastSeenAt` bump
- [x] Hash change → `detailScrapedAt` cleared
- [x] Missing paths from scrape → `isActive = false` (not delete)

### Stage 3 — Scrape
- [ ] Every listing has non-empty `externalPath`
- [ ] Scrape errors surface in company status (not silent empty)

### Stage 4 — Import
- [ ] Upsert key: `(companySlug, externalPath)`
- [ ] Unchanged `listingHash` → only `lastSeenAt` bump
- [ ] Hash change → `detailScrapedAt` cleared
- [ ] Missing paths from scrape → `isActive = false` (not delete)

### Stage 5 — List UI
- [x] **No** Good/Fair/Poor fit without parsed resume + job description
- [x] **No** match % without hash-valid `CareerResumeJobMatch`
- [ ] Filters do not hide active postings incorrectly

### Stage 6 — Detail
- [x] Lazy fetch respects 48h TTL unless forced
- [x] `descriptionHash` includes description + requirements
- [x] Hash change invalidates match cache

### Stage 7 — Resume
- [x] Match UI requires `ingestCompletedAt` + `structuredProfile.hasContent`
- [x] `targetRole` / `detectedDomains` alone do **not** enable match badges

### Stage 8 — ATS
- [x] Full score only with eligible resume + usable JD
- [x] One `recommendedForPosting` per posting
- [x] Cache hit requires matching description + resume hashes

### Stage 9 — Tracker
- [x] `workdaySourcePosting` ↔ `trackedApplication` round-trip (`JobBoardTrackerTests`)
- [x] Promote copies JD into `JobApplication`

## Normal vs abnormal

| Observation | Normal? | Action |
|-------------|---------|--------|
| 1800+ list rows, no match % | Yes | JD not loaded until detail opened |
| Good fit on every row without opening jobs | **No** | Gate list badges (`JobBoardMatchEligibility`) |
| Match % on never-opened job | **No** unless stale cache | Validate hash; purge stale rows |
| Resume file, no parse, match shown | **No** | Require `ingestCompletedAt` |
| `recommendedMatch` but `detailScrapedAt` nil | **No** | Data anomaly; hide badge |
| Requirements change, same match % | **No** | Rehash + invalidate |

## Test location

SwiftTesting suites: `CollegeTests/Features/Career/Openings/`

DEBUG audit: `JobBoardDataAudit` in Diagnostics center.

CI: `.github/workflows/career-jobboard-tests.yml`
