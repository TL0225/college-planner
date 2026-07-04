# College App — Full Codebase Audit Findings

**Generated:** 2026-07-01  
**Coverage:** **1374/1374** Swift files in [`audit-manifest.tsv`](audit-manifest.tsv)  
**Method:** Automated pattern sweep (`scripts/audit-sweep.py`) + deep-read per wave (Career, App/Data/Services, Assistant/Core/Packages/Tests) + manual verification of hot paths  
**Phase 5 fixes:** Deferred until user approves specific items

---

## Coverage summary

| Metric | Count |
|--------|------:|
| Total Swift files | 1374 |
| `audit_status=swept` (automated pass clean) | 1000 |
| `audit_status=deep_read` (line-by-line or hot-path read) | 374 |
| Concurrency `blocking` | 13 |
| Concurrency `stall` | 47 |
| Memory `high` | 5 |
| Memory `medium` | 41 |
| Dead `orphaned` | 4 |
| Dead `confirmed_dead` | 2 |
| Tests (`n/a_test`) | 301 |

**Not in automated timing:** No Instruments traces were run. Severity is architectural.

---

## Phase 1 — Concurrency & Main-Thread (blocking)

| File | Line(s) | Issue | Suggested fix |
|------|---------|-------|---------------|
| `College/Features/Career/Job Board/JobBoardSyncCoordinator.swift` | 229–245 | Per-page `MainActor.run { mergeJobBoardListImportPage }` blocks scraper actor | Buffer pages; `BackgroundServiceExecutor.persistOffMain` |
| `College/Core/Data/Repositories/CareerRepository+JobBoardImport.swift` | 42–85, 82–84 | N+1 `fetchOrCreatePosting`; `flushNow` + `bumpCareerRevision` every page | Batch-fetch paths; debounce save/revision until finalize |
| `College/Features/Career/Job Board/JobBoardSyncCoordinator.swift` | 254–258 | Duplicate full-list merge when `importedByPage` | Skip final merge; go to `finalizeJobBoardListImport` |
| `College/Features/Career/Job Board Scrapers/Workday/WorkdayScraper.swift` | 556, 852–866 | `maxAccumulatedJobs = 50_000` vs `maxListingsPerSync = 500` | Align cap; background persist |
| `College/Core/Data/Repositories/CareerRepository.swift` | (design) | `@MainActor`; job-board import uses main `ModelContext` | Route bulk ingest via `persistOffMain` |
| `College/Core/Data/Storage/AppDataStore.swift` | 72–74 | Sync `CollegeUnifiedCatalogStoreMigration` in `init` | Defer to background launch lane |
| `College/Core/Data/Storage/CollegeUnifiedCatalogStoreMigration.swift` | 67–219 | Full legacy SQLite → SwiftData copy on main | Detached task + isolated context + batch inserts |
| `College/Core/Platform/Services/BackgroundServiceOnDemand.swift` | 8–27 | All operations `@MainActor` despite "background" name | Add `runOffMain`; reserve for UI-only |
| `College/Features/Catalog/Ingest/CatalogSchoolImportService.swift` | 10–193 | Entire import on main; 500-row chunks + `catalogSave()` | DTO build off main; `persistOffMain` |
| `College/Features/Catalog/CatalogBundleSecurity.swift` | 84–92 | `Data` + `JSONDecoder` for bundles up to 50 MB on main | Verify/decode in `Task.detached` |
| `College/Features/Catalog/Store/CatalogStorePortableBridge.swift` | 36–55 | Mapped SQLite import into main context | Stream via `persistOffMain` |
| `Packages/CollegeCalendar/.../CalendarIntegrationManager.swift` | 1179–1316 | `eventStore.events(matching:)` over 545 days on `@MainActor` at launch | Detached EK snapshot → `CalendarSyncIngestService` |
| `College/Features/Academics/AuditSnapshotStore+LoadAudit.swift` | 11–336 | `buildAuditDegrees` on main; JSONDecoder per requirement in loops | `Task.detached` pure build; batch catalog lookups |
| `College/App/CollegeAppDelegate.swift` | 36–44 | `DispatchGroup.wait` on `applicationWillTerminate` (forbidden by project rules) | Async termination or bounded cooperative shutdown |
| `College/Core/Data/Repositories/CareerRepository+Resume.swift` | 83–84 | `Data(contentsOf:)` on `@MainActor` in heuristic scoring | Detached read or vault async path |

---

## Phase 1 — Concurrency (stall / high impact)

| File | Line(s) | Issue | Suggested fix |
|------|---------|-------|---------------|
| `College/Features/Career/Job Board/Views/JobBoardCompanyJobsView.swift` | 290–293 | `careerDidChangeToken` → full reload during import | Ignore token while scrape in flight |
| `College/Features/Career/Job Board/Views/JobBoardUnifiedJobsView.swift` | 377–393 | Semantic ranking embeds all postings | Cap concurrency; embed visible rows only |
| `College/Features/Career/Job Board/JobBoardSmartFilterEngine.swift` | 266–279 | Unbounded `TaskGroup` per posting embed | Limit 4–8 workers; cache `NLContextualEmbedding` |
| `College/Features/Career/Job Board Scrapers/Oracle/OracleHCMScraper.swift` | 24–57 | Up to 50k jobs; no `onListingsPage` | Wire streaming persist; cap listings |
| `College/Core/Services/CatalogBackgroundSyncRunner.swift` | 310–328, 1196–1232 | `importIncremental` on main per 250-course chunk | Buffer + `persistOffMain` |
| `College/Features/Overview/OverviewView.swift` | 1300–1302 | `rebuildStandingPageCache` on main in `.task` | Offload computation; snapshot on main |
| `College/Core/Security/SecurityManager.swift` | 349–379 | Vault migration: 5000 docs + per-file read on unlock | `BackgroundServiceExecutor.runWorkUnit` |
| `College/Features/Career/Services/CareerATSService.swift` | 131+ | Sequential embed+score; frequent `MainActor.run` | Batch embeddings; reduce main hops |
| `College/App/LaunchPreloadCoordinator.swift` | 118–174, 349–357 | Pipeline on `@MainActor`; spin-wait on store | Progress on main; work via `runWorkUnit` |
| `College/Core/Services/VaultFileOrganizer.swift` | (static) | Unsynchronized `undoBuffer` — race on concurrent organize | Lock or serial actor |

---

## Phase 2 — Memory

| File | Line(s) | Issue | Severity | Suggested fix |
|------|---------|-------|----------|---------------|
| `College/Features/Assistant/AIAssistantView.swift` | 224–228 | No `cancelActiveGeneration()` on disappear | high | Cancel generation + persist tasks |
| `College/Features/Assistant/AssistantWebPageCache.swift` | 14–46 | Up to ~120 MB in-memory (1500×80k chars) | high | Evict on pressure; disk-backed |
| `College/Features/Career/Job Board Scrapers/Workday/WorkdayScraper.swift` | 556+ | 50k listing accumulation in memory | high | Cap at `maxListingsPerSync` |
| `College/Features/Career/Job Board/Views/JobBoardUnifiedJobsView.swift` | 24–35 | 2000 full postings + embedding dict in `@State` | high | List DTO; paginate; clear on disappear |
| `College/Features/Career/Job Board/JobBoardSmartFilterEngine.swift` | 266–279 | Unbounded parallel NL embed tasks | high | Concurrency cap |
| `College/Features/Assistant/AssistantPolicyRAG.swift` | 105–154 | 1500 in-memory chunks + embeddings | medium | `MemoryPressureHandler` hook |
| `College/Features/Assistant/AssistantWebPageExtractor.swift` | 30–52 | Singleton WKWebView for app lifetime | medium | Teardown on idle/pressure |
| `College/Core/MemoryPressureHandler.swift` | 76–113 | Does not clear assistant caches | medium | Add `clearAssistantCaches()` |
| `College/Core/Data/Storage/ModelMergeCoalescer.swift` | 12–36 | Static dict retains `ModelContext` until flush | medium | Defer flush during bulk import |
| `College/Features/Career/Services/CareerNLSemanticEmbedding.swift` | 12–17 | New `NLContextualEmbedding` per call | medium | Cache shared instance |
| `College/Features/Career/Job Board/Views/JobBoardCompanyJobsView.swift` | 297–306 | Tasks not cancelled on disappear | medium | `.onDisappear` cancel |

---

## Phase 3 — Dead code

### Confirmed dead

| File | Symbol | Reasoning |
|------|--------|-----------|
| `College/Features/Career/Job Board Scrapers/ATSFingerprintStore.swift` | `extractCareersURL` | Zero call sites |
| `College/Features/Career/Job Board Scrapers/JobBoardPublicHubScrapeEngine.swift` | `onListingsPage` callback | Parameter never invoked |
| `College/Core/Data/Persistence/CollegePersistence+LegacyShims.swift` | `cleanupJobBoardRelationshipOrphans()` facade | Only wrapper; live path is `CareerRepository` |
| `College/App/AppShellMenuNotifications.swift` | `collegeToggleSidebar` | No post/receive |
| `College/App/PlannerMenuNotifications.swift` | `plannerExportPortalBackup`, `plannerImportPortalBackupMenu` | No post/receive |
| `College/Features/Career/Resumes/CareerResumeLibrary.swift` | `atsTierColor`, `atsGreenMinimum`, `atsYellowMinimum` | Superseded by `parserHealthTierColor` |
| `College/Features/Assistant/AssistantWebSearchSettings.swift` | deprecated `searx*` aliases | Migration-only |
| `College/Core/Platform/Services/BackgroundServiceDeprecatedShims.swift` | entire enum | Intentional compile guardrail |

### Orphaned (compiled, never presented)

| File | Symbol | Reasoning |
|------|--------|-----------|
| `College/Features/Career/Job Board/JobBoardMenuBarView.swift` | `JobBoardMenuBarView` | Logic duplicated in `CollegeMenuBarRoot`; never mounted |
| `College/Features/Overview/MultiDegreeOverviewCards.swift` | `AllDegreesProgressCard`, `AcademicCareerTimelineCard` | No nav/widget path |
| `College/Features/Overview/WidgetKit/EqualizerBarsView.swift` | `EqualizerBarsView` | Zero embed sites |
| `College/App/CatalogMenuBarProgressController.swift` | NSStatusItem path | `ensurePersistentStatusItem` empty; still in manifest |

### `#if false` / commented blocks

None found in Swift sources.

---

## Phase 4 — Rust interop

| Candidate | Verdict | Reason |
|-----------|---------|--------|
| Workday JSON parse | **Swift-optimize-first** | Bottleneck is main-thread SwiftData + UI, not decode (already on scraper actor) |
| Vector cosine / RAG | **Swift-optimize-first** | `VectorMath` uses Accelerate/vDSP; FTS5 limits candidates; consider sqlite-vec at scale |
| Job board NL embeddings | **Swift-optimize-first** | Fix concurrency + cache embedder |
| Bulk catalog/audit | **Swift-optimize-first** | `persistOffMain` + offload `buildAuditDegrees` |
| Rust FFI/XPC | **Not worth it now** | Revisit only after Swift fixes + Instruments shows >100ms numeric loops |

---

## Good patterns (reference for Phase 5)

| File | Pattern |
|------|---------|
| `College/Core/Data/Storage/CalendarSyncIngestService.swift` | `BackgroundServiceExecutor.persistOffMain` + isolated `ModelContext` |
| `College/Core/Platform/Services/BackgroundServiceExecutor.swift` | Standard off-main fetch/persist/runWorkUnit |
| `College/Features/Career/Job Board Scrapers/JobBoardScrapePacing.swift` | Actor-serialized rate limiting |
| `College/Features/Career/Job Board/JobBoardReadBridge.swift` | Detached fetch + main hydration |
| `College/Core/Utilities/VectorMath.swift` | vDSP cosine similarity |
| `College/Features/Assistant/PlannerVectorStore.swift` | Disk-backed SQLite + actor isolation |
| `College/Features/SyllabusAI/LocalLLMRunner.swift` | Actor + `MLXTaskQueue` |

---

## Phase 5 fix order (after user approval)

1. Job board: `persistOffMain`, debounce flush/revision, batch fetch, UI suppress during scrape, Workday cap
2. Launch: defer migration, offload EventKit, fix `BackgroundServiceOnDemand`
3. Memory: assistant cancel on disappear, embedding cap, pressure hooks
4. Dead code: delete only approved symbols
5. Rust: only if profiling justifies; keep Swift fallback

**Commit discipline:** one file or one clear issue per commit.

---

## Machine-readable index

Full per-file ratings: [`docs/audit-manifest.tsv`](audit-manifest.tsv)  
Regenerate automated sweep: `python3 scripts/audit-sweep.py` (then re-apply manual overrides for known findings)
