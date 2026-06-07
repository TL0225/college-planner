# College App — Performance File Manifest (Phase 5c)

**Generated:** 2026-05-30  
**Scope:** All **518** Swift files in `College/` (+ **60** in `CollegeTests/` not tabulated here).  
**Method:** Phase 5 module agents (deep) + Phase 5b gap inventory + Phase 5c six directory passes (file-level stall/memory notes).

**Machine-readable index:** [`performance-file-manifest-index.tsv`](performance-file-manifest-index.tsv) — every app file with `path`, `lines`, `module`, `coverage` (5b/5c), `risk_hint` (Y/N/P).

**Implementation plan:** [app_performance_sweep plan](../.cursor/plans/app_performance_sweep_309942bf.plan.md) — Master P0 backlog (18 items).

---

## Coverage summary

| Coverage | Files | Meaning |
|----------|------:|---------|
| **5c** (file-level notes) | ~347 | Calendar, Career, App, Settings, Catalog root, Intelligence, Academics, Courses, Location, Brightspace, Security, Overview, root loose |
| **5b** (directory inventory) | ~171 | Catalog/Ingest, PDF, Vector, Store; DesignSystem; Services; local store; SyllabusAI; Profile; Debug; Platform; Notifications; Utilities; Core |
| **Total** | **518** | 100% paths indexed in TSV |

| risk_hint | Files (heuristic + agent) | Notes |
|-----------|----------------------------|--------|
| **Y** | ~140+ | Agent-flagged or lines>1500 monoliths |
| **P** (partial) | 0 | Swept at sign-off Jun 2026 (5c/5b inventory + remediation pass) |
| **N** | ~90 | Tokens, models, trivial UI |

---

## Pipeline registry (all app-level)

| Pipeline | Entry | Main thread? | Memory heavy? |
|----------|-------|:------------:|:-------------:|
| `LaunchPreloadCoordinator` | Cold launch | Yes | Medium |
| `CatalogBackgroundSyncRunner` / `CatalogIngestPipeline` | Sync / onboarding | Yes | **Yes** |
| `CatalogPDFPipeline` | PDF schools | Mixed | **Yes** |
| `CatalogVectorIndexer` + `CatalogVectorIndexingLifecycle` | Post-commit | Mixed | **Yes** |
| `CatalogStoreCoordinator` | App delegate | Yes | **Yes** |
| `CatalogProgramRequirementsHydrator` | Settings / hydration | Yes | Medium |
| `CatalogWorkspaceHydrationCoordinator` | *(no callers)* | Yes | Medium |
| `ModelBootstrapService` / `LocalLLMRunner` | Launch / inference | Mixed | **Yes** |
| `LLMMemoryLifecycle` | Background only today | Yes API | **Yes** |
| `PlannerVectorIndexer` / lifecycle | CD save | Mixed | Medium |
| `VaultDocumentTextIndexer` | Vault | Mixed | Medium |
| `CalendarIntegrationManager` / `CalendarView` cache | Calendar tab | Yes | Medium |
| `CalendarSyncCoordinator` + providers | Sync | Mixed | Medium |
| `WorkdayJobBoardSyncCoordinator` / `WorkdayScraper` | Career | Mixed | Medium |
| `CareerIngestCoordinator` | Scene active | Mixed | Medium |
| `BrightspaceWebCoordinator` | App init | Yes | **Yes** |
| `WebShortcutCoordinatorPool` | Shortcuts | Yes | **Yes** |
| `RuntimeTelemetryMonitor` | `CollegeApp.init` | Yes | Low (overhead) |

---

## Phase 5c — Detailed findings by module

### Calendar (54 files)

**Hot files:** `CalendarIntegrationManager.swift` (5073), `AddCalendarItemOverlay.swift` (5218), `CalendarView.swift` (2457), `CalendarEventWritePipeline.swift`, `CalendarCacheEngine.swift`.

| Priority | Finding |
|----------|---------|
| P0 | `rebuildCachesAsync` filters all events on main before detached build; EventKit fallback in `shouldDisplayEvent` |
| P0 | `searchCalendarEvents` unbounded on `viewContext` |
| P1 | Wide `@FetchRequest` window (~120+ days); duplicate cache representations |
| P1 | Post-sync `CalendarCourseLinker.scanAndLink` on main |
| P1 | ICS full-text parse + `refreshAllObjects` |

*Full per-file table: see agent transcript in plan Phase 5c section or expand from TSV `module=Calendar`.*

---

### Career (52 files)

**Hot files:** `CareerWorkspaceView.swift` (2340), `persistence coordinator+Career.swift`, `WorkdayScraper.swift`, `WorkdayCompanyJobsView.swift`, `ICIMSScraper.swift`.

| Priority | Finding |
|----------|---------|
| P0 | `WorkdayScraper.applyFacetTags` re-scrapes full company per facet value |
| P0 | Scene-active ingest + reconcile + Workday refresh (duplicate with `onAppear`) |
| P1 | N+1 `fetchOrCreatePosting` during import |
| P1 | `WorkdayCompanyJobsView` UserDefaults read per row for hidden keys |
| P2 | Unbounded `seenKeys` in UserDefaults |

---

### App (42) + Settings (25)

**Hot files:** `OnboardingRootView.swift` (1876), `ContentView.swift` (1264), `LaunchPreloadCoordinator.swift`, `CollegeApp.swift`, `SettingsCatalogSyncSection.swift` (974), `SettingsCatalogSelectedProgramsBlock.swift` (582).

| Priority | Finding |
|----------|---------|
| P0 | `CatalogBackgroundSyncRunner` on `@MainActor`; in-memory PDF download |
| P0 | Launch preload duplicates CD + double Brightspace warmup |
| P0 | `reloadContextOptions` query storm (onboarding) |
| P0 | `dictionaryRepresentation()` settings preload |
| P1 | `migrateUniversitiesFromCurrentStore` every launch |

**5c risk Y count:** 18 of 67 files in App+Settings.

---

### Catalog root (39 files)

**Hot files:** `UniversalCatalogScraper.swift` (3595), `ModernCampusEngine.swift` (2669), `CatalogProgramRequirementsHydrator.swift`, `WebScraperService.swift`, `CourseLeafCourselistHTMLParser.swift`.

| Priority | Finding |
|----------|---------|
| P0 | Requirements hydrator on `@MainActor` |
| P0 | WKWebView in `WebScraperService` + `CatalogRenderedHTMLFetcher` |
| P0 | Bulk scrape memory (SwiftSoup DOM) |
| P1 | Bundle export full-university fetch |

**5c risk Y:** 18 of 39 root catalog files.

---

### Intelligence (68 files)

**Hot files:** `AIAssistantView.swift` (3607), `AIAssistantService.swift`, `AssistantAttachmentIngestor`, `AssistantWebPageExtractor`, `PlannerVectorIndexer`, `AssistantPolicyRAG.swift`.

| Priority | Finding |
|----------|---------|
| P0 | Serialized multi-hop MLX; no `LLMMemoryLifecycle.touch()` |
| P0 | Attachment OCR blocks send |
| P0 | `makePlannerSnapshot()` on main per message |
| P1 | `searchCatalogCourses` default backfill |
| P1 | Unbounded `AssistantPolicyRAGStore` |

**5c risk Y:** 32 of 68 files.

---

### Academics (16) + Courses (10) + Location (7) + Brightspace (5) + Security (5) + Root (2)

**Monoliths:** `AcademicsView.swift` (3678), `CourseDashboardView.swift` (2499), `MajorMinorDetailsView.swift` (2186).

| Priority | Finding |
|----------|---------|
| P0 | Duplicate credit recompute every `AcademicsView.body` |
| P0 | `loadAudit` on main + N+1 catalog lookup |
| P0 | Audit models use `UUID()` identities |
| P0 | `LocationPickerSheet` MapKit without debounce |
| P0 | `WebShortcutCoordinatorPool` never pruned |
| P0 | Brightspace double launch preload |
| Critical | `BrightspaceWebCoordinator`, `SecurityManager`, `DataWipeManager` |

---

### Overview (22 files)

**Hot files:** `OverviewView.swift` (2049) — production dashboard; WidgetKit grid **unwired** (`bootstrapBuiltIns()` never called).

| Priority | Finding |
|----------|---------|
| P0 | Syllabus PDF merge on main |
| P0 | `programRows` requirement progress every render |
| High | Dead widget platform — 5 widgets not registered |

---

## Phase 5b — Supplementary modules (indexed + selective notes)

### Profile (14 files)

| path | lines | risk | Notes |
|------|------:|:----:|-------|
| `Profile/AcademicIdentityView.swift` | 2220 | Y | `fetchMajors` inside menu `body` — P0 |
| `Profile/ProfileView.swift` | 786 | Y | Photo decode every render; progress on appear |
| `Profile/ProfileEditSheet.swift` | 625 | Y | Full-res photo load |
| `Profile/AcademicProfileEditFields.swift` | 854 | P | Program picker queries |
| Others | <562 | N/P | Achievements, experience, serialization |

### Services (23 files) — all indexed in 5b

**P1 gaps:** `VaultDuplicateDetector`, `DocumentClassifierService`, `PDFAnnotationView`, `VaultSummaryService` (LLM), `CloudIntegrationService` (folder scan on main).

### local store (17 files)

**Deep:** `persistence coordinator.swift` (11662), `PersistenceController.swift`, `CatalogRepository.swift`.  
**Gaps:** `AppBackupManager`, `+GraduationPlan`, entity extensions.

### SyllabusAI (16 files)

**Deep:** `LocalLLMRunner`, `LLMMemoryLifecycle`, `ModelBootstrapService`.  
**Gaps (large, unopened):** `SyllabusHeuristicExtractor` (872), `SyllabusReviewView` (1512), `SyllabusScheduleInference` (646).

### Catalog subdirectories (51 files)

| Subdir | Files | Pipeline role | Default risk |
|--------|------:|---------------|:------------:|
| `Ingest/` | 17 | IR + checkpoint → merge | P — CPU during import |
| `PDF/` | 16 | `CatalogPDFPipeline` extractors | P — RAM per PDF |
| `Vector/` | 10 | Embed + SQLite | Y — indexer P0 |
| `Store/` | 8 | Per-school SQLite | Y — migration P0 |

### DesignSystem (9), Notifications (4), Utilities (2), Debug (13), Platform (11), Degree (4), Core (2), WebShortcuts (2), Rust (1)

Indexed in TSV. **Deep:** `RuntimeTelemetryMonitor` only. **Degree:** `PrerequisiteValidator` — Phase 4 P0. **WebShortcuts:** pool prune P0.

---

## Cross-app P0 themes (from full 518-file audit)

1. LLM idle release + no launch preWarm  
2. Catalog sync off main thread; stream downloads  
3. Launch dedupe + defer migration + lazy WKWebView  
4. Academics audit off-main + credit snapshot cache  
5. Calendar cache/search off main  
6. Vector indexer streaming  
7. Web shortcut pool prune  
8. Onboarding program query cache  
9. Assistant `performBackfill: false`  
10. Overview PDF merge off-main  

---

## CollegeTests (60 files)

Not line-audited in Phase 5c. Performance-related: `LaunchPerformanceAcceptanceTests`, `CalendarCacheEnginePerfTests`, `LocalLLMRunnerMemoryTests`, `CatalogCourseSearchTests`, CourseLeaf regression fixtures.

---

## How to use this manifest

1. Filter TSV: `risk_hint=Y` or `lines>1000` for review queue.  
2. Implement from plan **Master P0 backlog** first.  
3. Re-run Instruments per module after fixes; update TSV `risk_hint` column.
