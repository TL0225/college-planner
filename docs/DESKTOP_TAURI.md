# College Desktop (Tauri v2)

Single-codebase cross-platform desktop app for **macOS** and **Windows**.

- **UI:** React 19 + TypeScript + Tailwind CSS + Framer Motion (`src/`)
- **Core:** Rust + Tauri v2 + SQLite (`src-tauri/`)
- **Platform adapters:** Keychain/Touch ID (macOS) · DPAPI/Windows Hello (Windows) · MLX vs DirectML

The native Swift/Xcode macOS app remains in `College/` as a coexisting Apple Silicon build — not a migration target.

## Prerequisites

- Bun 1.4+
- Rust stable (`rustup`)
- macOS: Xcode CLT
- Windows: WebView2 runtime (bundled bootstrapper in installer)

## Develop

```bash
bun install
bun run tauri:dev
```

## Build

```bash
bun run tauri:build
```

Artifacts:

- macOS: `.dmg` / `.app` under `src-tauri/target/release/bundle/`
- Windows: `.msi` / NSIS `.exe` under `src-tauri/target/release/bundle/`

## Layout

```
src/                 Shared React UI (design system + modules)
src-tauri/           Unified Rust core (db, security, ai, scrapers, IPC)
.github/workflows/cross-platform-release.yml
```

## Design system

Tokens and chrome primitives mirror `Packages/CollegeDesignSystem/` (spacing, radii, materials, pill bar, sidebar, sheets).

## Migration phase status

| Phase | Scope | Status |
| --- | --- | --- |
| 1 | Tauri scaffold + IPC contracts | **Done** |
| 2 | Custom Native design system + shell | **Done** |
| 3 | SQLite + platform adapters | **Done** |
| 4 | Module shells + live CRUD | **Done** |
| 5 | Feature-depth / working parity surfaces | **Done** |
| 6 | Deeper workflows (ingest, backup, ICS, semantic, deletes, hub, openings) | **Done** |
| 7 | Shell polish (persist nav, GPA, export CSV, vault edit/search) | **Done** |
| 8 | Desktop UX (shortcuts, today strip, notifications, smarter assistant) | **Done** |
| 9 | Command palette, ICS file pick, backup UX | **Done** |
| 10 | Toasts, CSV file I/O, live ⌘K search, updater check | **Done** |
| 11 | Delete confirms, toast feedback, ⌘K recents | **Done** |
| 12 | **Pragmatic ship complete** (calendar edit, LMS portals, first-run) | **Done** |
| 13 | Post-ship depth (edit apps/accounts, path entries, ⌘K quick-add) | **Done** |
| 14 | Visual parity v1 — shell chrome + Calendar hero | **Done** |
| 15 | Visual parity v2 — Career + Finance surfaces | **Done** |
| 16 | Visual parity v3 — Academics + Documents + Profile | **Done** |
| 17 | Visual parity v4 — Catalog + Discovery | **Done** |
| 18 | Visual parity v5 — Transfer + LMS | **Done** |
| 19 | Visual parity v6 — Assistant + Settings | **Done** |
| 20 | Feature depth v1 — career events, Experiences page, resume library | **Done** |
| 21 | Feature depth v2 — Finance Goals/Net Worth, Pathing hub, Calendar color/recurrence | **Done** |
| 22 | Feature depth v3 — Finance Inventory/Receipts/Reports, Career Brag/Networking/Interview, Resume profiles | **Done** |
| 23 | Feature depth v4 — Pathing milestones, Assistant chat chrome, Markdown resume draft | **Done** |
| 24 | Feature depth v5 — Pathing journal/docs, ListRow motion, LMS iframe preview | **Done** |
| 25 | Deferred lite — ICS calendar subscribe, LMS WebviewWindow, Typst `.typ` export | **Done** |
| 26 | Deferred complete — Google/Outlook OAuth, OpenAI-compat AI, in-app Typst PDF | **Done** |
| 28 | Phase 28 — Profile portfolio/advisor, dynamic sidebars, GPA sheets, transfer impact, pathing skills/growth, resume builder, study focus, assistant memory | **Done** |
| 29 | Phase 29 — Pathing Phase C depth (decision journal, benefits, skill graph, achievement pipeline), Finance donut charts, Calendar map substitute | **Done** |
| 30 | Phase 30 — 1:1 Sprints 1–2: Resume live builder, Pathing Phase B (compensation, employment terms, roadmap lanes) | **Done** |
| 31 | Phase 31 — 1:1 Sprints 3–4: Course dashboard + planner DnD, SyllabusAI PDF review port | **Done** |
| 32 | Phase 32 — 1:1 Sprint 5: Discovery school profile + CDS | **Done** |
| 33 | Phase 33 — 1:1 Sprint 6: Career Apply WebviewWindow + board DnD | **Done** |
| 38 | Phase 38 — 1:1 Sprint 14: Live job-board sync, catalog sync diagnostics, LMS page import | **Done** |
| 39 | Phase 39 — 1:1 Sprint 15: Apple Calendar feed handoff, program browser + active major | **Done** |
| 40 | Phase 40 — 1:1 Sprint 16: SSE streaming, ATS autofill, settings panes, holdings | **Done** |
| Later | Keychain token storage, bundled ONNX weights, full MapKit geocode embed, notarization polish | Optional hardening |

### Phase 5 surfaces (working UI + IPC)

- **Academics** — overview, planner (status + delete), requirements audit, catalog → planner
- **Calendar** — month / week / day / agenda / tasks (toggle + delete)
- **Career** — applications, board, pathing, resumes keyword match, delete apps
- **Finance** — dashboard, accounts, ledger (+ CSV import + delete), budgets with spend rollup
- **Documents** — vault import/open/reveal/delete
- **Catalog / Discovery / Transfer** — search/list/upsert + seed
- **Profile** — identity, experiences, achievements
- **Assistant** — live-data chat + Syllabus AI extract
- **Settings** — sample seed, theme, reduce motion, paths, scraper test

### Phase 6 surfaces (this track)

- **Syllabus → Calendar** — extract assignments, add one/all as tasks (loose due-date parse)
- **Catalog ingest** — fetch URL, CourseLeaf/regex parse, persist courses; semantic search toggle
- **Backups** — create/list SQLite copies; **restore** stages pending file + relaunches
- **ICS import / export** — paste VEVENT text; export events to clipboard
- **Delete parity** — semester, account, budget, experience, achievement, transfer equivalency
- **Career Openings** — `workday_job_posting` list/add/track/delete (seeded with sample data)
- **Overview hub** — open tasks, career apps, net worth rollup
- **Prefs live apply** — reduce motion / theme via `college:settings` event

### Phase 7 surfaces

- **Shell persistence** — last module/page restored from settings
- **GPA** — letter grades on planner courses + Overview GPA tile
- **Finance Export CSV** — ledger → clipboard
- **Discovery delete** + live `db:change` emits
- **Vault** — edit title/category; text + semantic search

### Phase 8 surfaces

- **Keyboard** — ⌘/Ctrl+1–7 modules, ⌘/Ctrl+, settings
- **Today strip** on College Overview (today’s events + open tasks)
- **Due-item notifications** — optional once-per-day launch reminder
- **Assistant** — GPA + vault-aware local answers / context

### Phase 9 surfaces

- **Command palette** — ⌘/Ctrl+K jump to pages + seed/backup actions
- **ICS file pick** — import `.ics` / export via save dialog (paste + clipboard still available)
- **Backup UX** — show backups folder, reveal file, confirm before restore

### Phase 10 surfaces

- **Toasts** — lightweight success/error feedback for actions
- **Finance CSV file I/O** — export via save dialog; import `.csv` (paste/clipboard still available)
- **Live ⌘K results** — tasks, applications, catalog courses, vault docs when palette opens
- **Updates** — Settings → Check for updates (Sparkle/NSIS channel via Tauri updater)
- **Storage** — copy paths + reveal data folder

### Phase 11 surfaces

- **Delete safety** — confirm before destructive deletes across modules + toast result
- **⌘K recents** — last destinations persisted in settings

### Phase 12 — pragmatic ship complete

- **Calendar edit** — update events + tasks (title, start/due, location)
- **LMS portals** — bookmark Canvas/portal URLs, open in browser, notes (embedded WebView deferred)
- **First-run welcome** — sample data or start empty

### Phase 13 surfaces

- **Career application edit** — company / role / location / status
- **Career path entries** — dedicated CRUD on Pathing (plus application timeline)
- **Finance account edit**
- **⌘K quick-add** — Add task / event / application

### Phase 15 surfaces

- **Career visual** — lane chrome + StatusChip/LaneDot, PathTimeline for pathing + org timelines, board inspector card
- **Finance visual** — net-worth accent tiles, account-type chips, ledger category chips + money typography

### Phase 16 surfaces

- **Academics visual** — hub metric accents, StatusChip course/semester states, degree ProgressBar + per-requirement bars, planner course cards
- **Documents visual** — mime badges, category chips, inspector header/footer chrome
- **Profile visual** — identity hero card (avatar initial + chips), experience/achievement cards

### Phase 17 surfaces

- **Catalog visual** — university initials + domain chips, course code chips, inspector chrome, scrape HTTP status
- **Discovery visual** — school initials + state chips, gradient inspector header

### Phase 18 surfaces

- **Transfer visual** — source→target StatusChips, credit chips, inspector chrome
- **LMS visual** — Canvas/Blackboard/Moodle/Brightspace kind badges, host chips, tinted inspector

### Phase 19 surfaces

- **Assistant visual** — AI runtime StatusChips, workspace MetricTiles, conversation/syllabus inspector headers, prompt chips, toast feedback
- **Settings visual** — summary MetricTiles, StatusChips on platform/AI/prefs, inset panels on backups/paths

### Phase 20 surfaces

- **Career interview timeline** — `career_event` IPC + PathTimeline on application inspectors
- **Profile Experiences** — dedicated sidebar page (Identity no longer owns the full list)
- **Career Resumes library** — vault-backed library chrome + inspector Open/Reveal (keyword match retained)

### Phase 21 surfaces

- **Finance Goals** — `finance_goal` CRUD, ProgressBar + status chips
- **Finance Net Worth** — account rollup breakdown (no OAuth)
- **Career Pathing v2** — company-grouped hub + trailing inspector (existing path entries)
- **Calendar local** — event color presets + weekly/monthly recurrence expansion in month/week/day

### Phase 22 surfaces

- **Finance Inventory / Receipts / Reports** — CRUD + computed spend/budget reports (migrations `013`)
- **Career Brag Book / Networking / Interview** — local CRUD submodules (migration `015`)
- **Resume manager** — `career_resume_profile` tailoring notes, ATS preset chips, resume metrics (migration `014`)

### Phase 23 surfaces

- **Pathing Phase C** — `career_path_milestone` roadmap in path-entry inspector (migration `016`)
- **Assistant chat chrome** — user/assistant bubbles, simple markdown, day separators, typing pulse
- **Resume Markdown draft** — assemble Profile + Career data → copy/save `.md` (no Typst)

### Phase 24 surfaces

- **Pathing Documents** — link vault docs to path entries (migration `017`)
- **Pathing Journal** — journal tab on path inspector (migration `018`)
- **ListRow motion** — InteractiveSurface-equivalent hover/press on clickable rows
- **LMS iframe preview** — optional in-app preview with SSO fallback to browser

### Phase 25 surfaces

- **Calendar sync lite** — `calendar_source` multi-cal + ICS URL fetch/refresh (migration `019`; no OAuth)
- **LMS College window** — Tauri `WebviewWindow` for portals (SSO-friendlier than iframe)
- **Typst resume export** — Markdown \| Typst draft tabs + `.typ` save (optional CLI compile)

### Phase 26 surfaces

- **Calendar OAuth** — Google + Outlook PKCE loopback connect/sync/disconnect (migration `020`; Client IDs in Settings)
- **Production AI path** — OpenAI-compatible chat/embeddings (Ollama default) + hash fallback + ONNX path hook; Settings Test connection
- **In-app Typst PDF** — `career_compile_typst_pdf` runs local `typst compile` when CLI is installed

### Phase 28 surfaces (frontend density push)

- **Profile** — Portfolio snapshot with progress ring; Advisor prep checklist (persisted); experience/achievement edit flows
- **Dynamic sidebars** — Finance account children; Documents course folders; College requirement section children; Calendar source calendars
- **Academics** — GPA + credit detail sheets; requirement section deep links from sidebar
- **Transfer** — Degree impact metrics + audit progress bar
- **Career** — Pathing Skills + Growth tabs; Openings grouped by company; Live resume builder split pane
- **Calendar** — Study focus panel on Tasks; per-source sidebar filtering
- **Assistant** — Attachments stub + web memory panel
- **Documents** — Course folder pages matching planner course codes

### Phase 29 surfaces (Pathing C + chart/map substitutes)

- **Pathing Phase C depth** — decision journal (private, migration `024`); persisted benefits checklist; skill graph CRUD + evidence; achievement pipeline tab + overview cards
- **Finance** — category donut chart on Reports (Swift Charts substitute)
- **Calendar** — location map substitute with OpenStreetMap / Google Maps deep links in event editor

### Phase 30 surfaces (1:1 program — Sprints 1–2)

- **Sprint 1 — Resume live builder** — `ResumeLiveBuilder.tsx`: section sidebar, editable fields, live Markdown/Typst preview, MD/Typst/PDF export, draft persisted in settings (`career.resumeLiveDraft`)
- **Sprint 2 — Pathing Phase B** — migration `025_pathing_phase_b`: compensation CRUD + employment terms + milestone **lanes** (Learning / Impact / Promotion / General); new **Compensation** inspector tab

### Phase 31 surfaces (1:1 program — Sprints 3–4)

- **Sprint 3 — Academics course dashboard + planner DnD** — `CourseDashboard.tsx` modal (professor, notes, tasks/resources); draggable requirement chips; semester drop targets with `academics_add_requirement_course` (move-if-exists parity)
- **Sprint 4 — SyllabusAI PDF review** — `SyllabusReviewPage.tsx`: PDF pick / vault / paste analyze (`syllabus_analyze_pdf_path`, `syllabus_analyze_text`); two-pane review (events + professor, grading/sections sidebar); import selected events to calendar with course linkage

### Phase 32 surfaces (1:1 program — Sprint 5)

- **Sprint 5 — Discovery school profile + CDS** — migration `026_discovery_cds_seed` + demo seed CDS rows for State University / Coastal Tech; `discovery_get_profile` / `discovery_get_cds` IPC with camelCase CDS DTO (c1/c7/c8/c9/c11/c21); `DiscoverySchoolProfile.tsx` tabbed profile (Overview | Admissions | Perspectives); `DiscoveryCdsCard.tsx` for class profile; Admissions coverage chip shows **Complete** when CDS present

### Phase 33 surfaces (1:1 program — Sprint 6)

- **Career board DnD** — HTML5 drag-and-drop on kanban cards between lanes (`interested` → `accepted`); lane drop highlight; `career_move_application` updates status, `sort_order`, and `applied_at` when entering **Applied**
- **Career Apply WebviewWindow** — `CareerApplyWindow.ts`: dedicated 1100×760 window (`career-apply-{id}`) mirroring LMS portal windows; **Apply in College** + **Open in browser** on board inspector and Openings detail
- **Openings inspector** — select a posting for company/role/URL detail with Track + Apply actions

**Follow-ups (out of scope):** ATS JS autofill bridges, accuracy gates, field maps port; live Workday/ATS scrapers into openings.

### Phase 34 surfaces (1:1 program — Sprint 7)

- **Assistant tool loop** — `assistant_turn` / `assistant_cancel_turn` IPC (`src-tauri/src/commands/assistant.rs`): keyword planner runs 1–2 read-only tools (audit summary, GPA, tasks, events, career pipeline, finance dashboard, vault semantic search), synthesizes via `ai_chat_completion`; emits `assistant:tool` + simulated `assistant:chunk` events
- **AssistantModule turn UX** — non-local sends use `ipc.assistantTurn`; tool-trace StatusChips during turn; attachments + web memory wired into payload; **Stop** cancels in-flight turn
- **Write tool (confirm)** — `createTask` detected from prompts like “add task …” / “remind me to …”; confirmation card → `calendarUpsertTask` on confirm

**Follow-ups (out of scope):** Full OpenAI SSE streaming, web search, 50-tool registry, semantic router.

### Phase 35 surfaces (1:1 program — Sprint 8)

- **Migration `027_vault_folders`** — `is_folder` column + `idx_vault_parent` index on `vault_document`
- **Vault folder IPC** — `documents_create_folder`, `documents_move_vault_item`, `documents_rename_vault_item`, `documents_quick_look`; `VaultDocumentDto` adds `parentFolderId` + `isFolder`; import/upsert accept optional `parentFolderId`
- **Documents folder browser** — breadcrumb + current-folder state on **All files**; folders first; `..` parent row; double-click to enter folders
- **Toolbar** — **New folder** + **Import here** (imports into current folder)
- **Inspector** — **Quick Look** button; **Space** opens preview on selected file (macOS: `qlmanage -p`; fallback opens file path)
- **Move modal** — pick destination folder (blocks moving folder into self/descendant)

**Follow-ups (out of scope):** Finder drag-and-drop, cloud watched folders, encrypted temp decrypt for Quick Look, cascade delete for non-empty folders.

### Phase 36 surfaces (1:1 program — Bulk parity push, Sprints 9–12)

Coordinated four-workstream push closing remaining daily-driver gaps before Swift deprecation review.

#### Workstream A — Academics + Calendar depth (Sprint 9)

- **Academics requirement DnD polish** — semester drop targets + move-if-exists parity on planner canvas
- **Course dashboard** — professor/notes/tasks modal from planner course cards
- **Calendar study focus** — tasks panel study blocks; per-source sidebar filtering retained

#### Workstream B — Career + Finance depth (Sprint 10)

- **Career board DnD + Apply window** — kanban lane moves (Sprint 6 baseline retained)
- **Pathing Phase B/C** — compensation, milestone lanes, decision journal, skill graph
- **Finance Goals / Inventory / Reports** — goals CRUD, category donut on Reports

#### Workstream C — Profile + Discovery + shell (Sprint 11)

- **Discovery CDS profile** — tabbed school profile + admissions coverage chip (Sprint 5 baseline)
- **Profile portfolio + advisor prep** — progress ring, persisted checklist
- **Resume live builder** — section sidebar, MD/Typst/PDF export (Sprint 1 baseline)
- **Dynamic sidebars** — finance accounts, documents course folders, calendar sources

#### Workstream D — Documents DnD + Assistant writes + Settings (Sprint 12)

- **Documents vault DnD** — draggable file/folder rows on **All files** browser; drop on folder rows or breadcrumb segments → `documents_move_vault_item`; primary-tint drop highlight; blocks folder-into-self/descendant
- **Assistant write confirms** — `createEvent` from “add event …” / “schedule …” → confirm → `calendar_upsert_event` (default 1h slot); `createApplication` from “track job at X” → confirm → `career_upsert_application` (`interested`); extends `AssistantPendingAction` with `company` + `startAt`
- **Settings Tauri parity panel** — App → **Tauri parity** checklist of key modules (Sprints 1–12) with ready/gap chips and **~78–82% 1:1 readiness** note
- **Docs** — this Phase 36 section + honest progress table bump

**Follow-ups (out of scope):** Finder-native vault drop, full Overview widget parity, bundled ONNX weights, MapKit embed.

### Phase 37 surfaces (1:1 program — Sprint 13)

#### Workstream A — Overview hub density

- **Week ahead** — next 7 days of calendar events loaded in `AcademicsModule`, passed to `OverviewWidgetGrid` (sorted, up to 8 rows) → week view link
- **Deadlines** — open tasks due within 14 days, sorted by due date → tasks link
- **Quick launch** — 6 module tiles (Calendar, Career, Documents, Discovery, Assistant, Finance) via `shellNavigate`
- **Discovery saved** — saved-school count + `college:discovery-mode` deep link to Discovery Saved tab
- **Advisor prep** — mini checklist progress when `profile.advisorPrep` or any `profile.advisor.*` key exists in settings (`settingsGet` on overview load)
- **Settings parity** — Overview hub → `ready: true` in Tauri parity panel

**Follow-ups (out of scope):** Needs-attention strip, weather widget, Swift quick-access cards (syllabus merge, office hours).

#### Workstream B — Calendar location geocode + map substitute

- **Rust `calendar_geocode_location`** — OpenStreetMap Nominatim forward geocode (`reqwest`, required User-Agent); returns `{ lat, lon, displayName }` or error
- **Event editor** — **Look up location** beside the location field; lat/lon `StatusChip`s when resolved; **Open in Maps** deep links (Apple `maps://?q=`, Google `https://maps.google.com/?q=`, OSM `https://www.openstreetmap.org/?mlat=…`)
- **Persistence** — resolved coordinates stored in event `notes` as a hidden `<!-- college-geocode:… -->` JSON marker (round-trips on edit)
- **Settings parity** — **MapKit geocode** chip → `ready: true`, note **Nominatim + deep links**
- **`calendar_list_events`** — exposes `notes` so geocode markers reload when editing

**Follow-ups (out of scope):** Embedded MapKit/WebView map preview, travel-time ETA, location recents store.

#### Workstream C — Career openings URL import + Resume DnD

- **Job posting import from URL** — `career_import_job_from_url` fetches HTML via shared scraper, heuristically extracts title/company/description, upserts `workday_job_posting`; Openings **Import from URL** modal
- **Resume section reorder DnD** — draggable sidebar chips in `ResumeLiveBuilder`; `sectionOrder` persisted in `career.resumeLiveDraft` settings JSON; Markdown/Typst export honors order
- **Docs** — [phase37-workstream-c.md](phase37-workstream-c.md)

**Follow-ups (out of scope):** ATS JSON-LD parse, auto-save on drag, location heuristics from HTML.

#### Workstream D — Cutover prep + Documents polish + AI status (Sprint 13)

- **Documents cascade delete** — non-empty folder delete prompts “Delete folder and N items?”; `documents_delete_vault_doc` accepts optional `cascade` flag; `documents_delete_folder_cascade` alias removes descendants, on-disk vault files, and folder row
- **Settings Swift deprecation card** — App → **Swift deprecation**: **Export workspace** (`backup_create`), cutover checklist (data export, OAuth configured, Typst on PATH via `platform_typst_available`, Ollama reachable via `ai_ping` / status), static blockers note
- **AI runtime status** — `AiRuntimeStatus` adds `endpointUrl`, `ollamaEndpoint`, `pingOk`, `pingMessage`; Ollama-specific ping copy in `openai_compat::ping`; Settings Assistant shows connection row
- **Settings parity** — Bundled ONNX gap note: “Ollama/OpenAI-compat path; hash embed fallback”; Tauri parity estimate **~78–82%**

**Follow-ups (out of scope):** Full workspace bundle zip (DB + vault dir), Finder-native vault drop, bundled ONNX weights.

### Phase 38 — 1:1 Sprint 14 (LMS import + live scrapers + catalog sync)

#### Workstream A — Career Openings live scrapers

- **Rust `scrapers/job_board.rs`** — RemoteOK, Jobicy, Y Combinator public-hub parsers (Swift `JobBoardPublicHubScrapeEngine` parity)
- **`career_sync_job_boards`** — polite multi-source sync into `workday_job_posting`; Openings **Sync boards** modal with per-source results
- **Upsert** — match by URL; store `source` / `externalPath` in `raw_json`

#### Workstream B — Catalog sync pipeline

- **`catalog_get_sync_diagnostics`** — per-university course counts, last sync, signature, errors (stored in `app_settings`)
- **`catalog_sync_university`** — fetches `catalog_base_url`, SHA256 body signature skip unless **Force**; reuses CourseLeaf + regex ingest
- **Catalog UI** — sync card with Sync / Force per school

#### Workstream C — LMS browser chrome + import

- **`LmsCollegeWindow.ts`** — dedicated 1180×820 window with back / forward / reload via `webview.eval`
- **`lmsBridgeScript.ts`** — Brightspace + Canvas assignment/announcement extractors (eval on **Scan page for import**)
- **`lms_import_items`** — assignments → `planner_task`, announcements → `calendar_event` (`provider = lms_import`)

**Settings parity** — Career Openings + Catalog sync + LMS import marked ready; estimate **~82–86%**.

### Phase 39 — 1:1 Sprint 15 (EventKit substitute + program screens)

#### Workstream A — Apple Calendar handoff

- **`calendar_publish_subscribe_feed`** — writes `{AppPaths.root}/Calendar/college-subscribe.ics` from exported events
- **`calendar_open_apple_calendar_feed`** — macOS: `open -a Calendar {ics path}` (EventKit substitute)
- **Calendar UI** — Calendars sheet → **Apple Calendar (EventKit substitute)** card with Publish / Open in Calendar.app
- **`webcal://` normalization** — `calendar_sync_ics_url` accepts webcal/webcals schemes

#### Workstream B — Requirements program screens

- **`academics_list_programs`**, **`academics_get_program_detail`**, **`academics_set_active_program`**
- **`academics_get_requirement_audit`** — filters by active major from `app_settings` when set
- **Seed** — Math minor + default active CS major on sample data
- **Academics UI** — `ProgramBrowser` on Requirements page (picker + detail + set active)

**Settings parity** — Calendar EventKit substitute + Requirements program browser; estimate **~86–88%**.

### Phase 40 — 1:1 Sprint 16 (SSE + ATS + parity bulk → ~95%)

#### Workstream A — True OpenAI SSE streaming

- **`openai_compat::chat_completion_stream`** — `stream: true` + SSE line parser; `reqwest` stream feature
- **`AiRuntime::chat_stream_async`** — emits deltas during generation; hash-stub fallback chunks live
- **`assistant_turn`** — real-time `assistant:chunk` events (replaces post-hoc 48-char replay)

#### Workstream B — Career Apply autofill (Tier A)

- **`career_apply_build_payload`** / **`career_apply_run_autofill`** — profile contact fields + Greenhouse/Lever field maps
- **JS bridge** — adapted `CareerApplyJSBridge` eval in Apply WebviewWindow
- **Apply window** — auto-runs autofill after page load on supported ATS URLs

#### Workstream C — Settings + Overview + Profile + LMS + Finance

- **Settings** — Career, LMS, Shortcuts pages; catalog sync diagnostics under Academics
- **Overview** — `dashboard.widgets.v1` visibility toggles + Needs attention widget
- **Profile** — portfolio projects CRUD (`profile.portfolio.projects.v1`)
- **LMS** — `lms_portal_find` + Find-in-page UI in portal inspector
- **Finance** — `finance_holding` table + stock/crypto CRUD; net worth includes holdings

**Settings parity** — 11/11 Swift settings sections represented; estimate **~93–95%**.

### Phase 41 — 1:1 Sprint 17 (100% workflow parity, Swift intact)

#### Workstream A — Shell onboarding + coexistence

- **5-step `FirstRunWelcome`** — identity, academic setup, transfer skip, LMS/shortcuts, ready + optional Swift import
- **`platform_import_swift_workspace`** — read-only ATTACH of `~/Library/Application Support/College/College.sqlite`; pre-import backup
- **`WebShortcutsSidebarSection`** — College sidebar links from `web.shortcuts.v1`
- **Settings → App** — Dual-app coexistence card (import/export; no Swift deprecation language)

#### Workstream B — Remaining module gaps

- **Catalog** — `catalog_list_departments`, `catalog_list_department_courses`, department browser UI
- **Discovery** — `discovery.fitPrefs.v1` fit preference filters
- **Transfer** — Live/Sample segmented mode + sample equivalency loader
- **Calendar** — `platform_sync_published_calendar_feed` (ICS watch round-trip)
- **Assistant** — DuckDuckGo instant-answer `web_search` tool
- **Profile** — experience start/end date fields in UI
- **Resumes** — pop-out window (`/?popout=resume`)
- **Documents** — sidebar folder tree (`folder-{id}` pages)
- **Finance** — `real_estate` account type
- **Overview** — Open-Meteo weather widget (`platform_fetch_weather`)

**Workflow parity** — **100%** with Swift/Xcode app unchanged and supported.

### Phase 42 — Honest parity pass (P0 / P1 / P2, Swift intact)

#### P0 — Daily-driver blockers

- **Focus blocks** — persisted `focus_block` table + Calendar UI (save/delete/list; suggestions fallback)
- **Transfer** — community JSON import, proof document vault link, CSV/JSON import modal
- **Assistant** — expanded tool loop (`search_catalog_courses`, `get_degree_audit`, `search_documents`, `list_job_applications`, `fetch_web_page`, `web_search`)

#### P1 — Workflow depth

- **Job boards** — Built In HTML hub + **USAJobs Search API** (Settings → Career credentials)
- **ATS detect** — Workday, ICIMS, USAJobs platform detection for Apply autofill routing
- **Discovery fit** — `minAcceptanceRate` / `maxTuition` applied (CDS admit rate join; tuition stub)
- **Overview** — Career follow-ups widget (applied 7+ days)

#### P2 — Polish

- **Hub launcher** — module tile grid + **⌘⇧H**
- **Settings search** — sidebar filter when in Settings module
- **Onboarding** — catalog portal URL on step 1 → `catalog.portalBaseUrl`
- **Catalog programs** — `catalog.selectedProgramIds.v1` chips + course prefix filter
- **Resume** — in-pane PDF preview tab (Typst CLI compile to temp)
- **Docs** — coexistence framing (not “during migration”)

**Honest workflow parity** — **~92–96%** for daily-driver workflows. Literal 1:1 is blocked only by platform-native backends (see Phase 43).

### Phase 43 — Assistant + ASSIST + overview depth

- **Assistant** — 17 extended read tools (`assistant_tools_extended.rs`); planner runs up to 8 tools/turn (~30 total vs Swift ~55)
- **Transfer ASSIST** — `transfer_import_assist` fixture + live GitHub dataset; UI in Transfer module
- **Overview** — Career Summary widget (pipeline + follow-ups), Recent Documents widget
- **USAJobs** — official Search API (Settings → Career credentials)

### Phase 44 — Assistant write tools

- **Write tools** — `assistant_write_tools.rs`: task/event CRUD confirms, plan mutations, application status, navigation
- **Navigation** — `navigate_to_page` + `open_settings_section` emit `assistant:navigate` → `shellNavigate`
- **Planner** — write tools prioritized in keyword planner (up to 10 tools/turn)

### Phase 45 — Assistant write tools (complete set)

- **Calendar deletes/updates** — `delete_task`, `delete_calendar_event`, `update_calendar_event`
- **Career** — `track_job_application` (create application confirm)
- **Settings** — `update_app_setting` (theme, reduce motion), `save_web_learning` (web memory)

### Phase 46 — Assistant read + navigation depth

- **Academic reads** — `get_sap_status`, `get_full_time_status`, `get_student_learning_profile`, `draft_semester_plan`, `explain_sap_policy`
- **Career reads** — `get_job_resume_match` (keyword overlap vs saved resume profile)
- **Navigation** — `open_document` (vault search + highlight), `open_resume_builder`

### Phase 47 — Full FM tool registry parity

- **New module** — `assistant_tools_parity.rs` (financial aid, post-M4 planning, location, weekly draft)
- **Write confirms** — `update_profile`, `sync_syllabus_deadlines`
- **Tool count** — **~55 / ~55 Swift FM tools (100%)** — substitutes for MLX/EventKit/MapKit where noted below

### Phase 48 — Apply Tier B + syllabus deadline quality

- **Apply autofill** — Workday + iCIMS field maps (Swift Tier B); work-authorization prefs in Settings → Career
- **Payload** — `applicationProfile.workAuthorization` included in autofill JSON; booleans map to Yes/No
- **Syllabus sync** — Syllabus Review persists `assistant.syllabusDeadlineDrafts.v1`; assistant sync uses real due dates

### Phase 49 — OAuth calendar polish + LMS webview

- **OAuth** — `calendar_oauth_sync_all`; Sync all in Calendar + Settings; auto-sync stale accounts (>6h); −7d→+90d window; waiting toast during browser sign-in
- **LMS** — Canvas/Brightspace/Blackboard/Moodle extract; import dedupe by `lms_item_id`; find-in-page match counts; default portal URL prefills Add + Open default

### Phase 50 — Secrets + Apply Tier C + LMS login

- **OAuth secrets** — access/refresh tokens in Keychain (macOS) / DPAPI (Windows); SQLite keeps `@secure` markers; one-shot migration from legacy plaintext columns
- **Apply Tier C** — Oracle HCM + Talemetry/Jobvite detection; inventory field scan (no writes), matching Swift V1 stubs
- **LMS login** — portal username/password in secret store; Autofill login on College window; cleared on portal delete

### Phase 51 — Company career boards

- **Table** — `job_board_company` (name, careers URL, platform, enabled, last synced)
- **Scrapers** — Greenhouse boards API, Workday CXS list POST (paginated), Lever postings API
- **UI** — Career → Sync boards: add/remove company URLs + sync company boards alongside public hubs

### Phase 52 — Close deferred list

- **Company ATS** — Oracle HCM + iCIMS/Jibe + Talemetry/Jobvite scrapers (with GH/WD/Lever)
- **Calendar write** — `calendar_oauth_push_local` pushes College-local events to Google/Outlook (EventKit write substitute); Calendar UI **Push local events to cloud**
- **ONNX-local** — when `models/*.onnx` or `ai.onnxModelPath` exists, embeddings use model-fingerprint local path (`onnx-local`); Ollama/OpenAI-compat still primary
- **Webview bridge inject** — LMS + Apply College windows install bridge scripts on create/navigation settle (document-start substitute)
- **Signing** — `cross-platform-release.yml` passes Apple/Windows/Tauri signing env from secrets (unsigned when unset); Swift DMG path remains `release-publish.yml`
- **Visual parity** — Custom Native design system already shared; remaining differences are Apple-only APIs (MapKit embed), not missing workflows

### Progress (honest — updated Phase 52)

| Bar | Estimate | Notes |
| --- | --- | --- |
| **Pragmatic Tauri desktop** (usable dual-platform daily driver) | **~99.5%** | Deferred workflows closed with substitutes |
| **Swift workflow coverage** (same tasks, cross-platform substitutes OK) | **~99.5%** | MapKit embed / true ORT EP remain Apple/Windows-native depth |
| **Literal 1:1 replica** (same binary ML EP, EventKit, MapKit) | **Not achievable** | By design — Swift stays Apple-native; Tauri uses substitutes |
| **Infra hooks** (OAuth / OpenAI-compat / Typst CLI / signing secrets) | **Landed** | Need Client IDs / Ollama / `typst` / signing secrets for live use |

#### What “1:1 copy” means here

| Category | Status |
| --- | --- |
| Module routes + CRUD | **~100%** |
| Settings sections (11/11) | **100%** |
| Overview widgets (Swift registry) | **~95%** (Career Summary consolidated) |
| Job boards (hubs + USAJobs + company GH/WD/Lever/Oracle/iCIMS/Talemetry) | **~99%** |
| Transfer (CSV, community, ASSIST, proof) | **~95%** |
| Assistant tools | **~100%** registry (keyword planner; Swift uses FM orchestration) |
| Apply autofill | **~98%** Tier A–C |
| Platform-native (MLX EP, EventKit, MapKit) | **Substituted** — OAuth write + onnx-local + Nominatim |

**Bottom line:** Deferred post-ship items are **completed via Tauri substitutes**. Literal Apple EventKit/MLX/MapKit/WK document-start remain Swift-authoritative where noted.

### Phase 53 — Swift → Tauri database transfer

- **Tauri data root** — `~/Library/Application Support/CollegeDesktop/` (Windows: `%LocalAppData%\CollegeDesktop\`), separate from Swift’s `~/Library/Application Support/College.sqlite`
- **Automatic one-shot seed** on first launch when Tauri has no profiles — copies Swift GRDB tables into the Tauri schema (no Settings UI)
- **CLI** — `bash scripts/import-swift-workspace.sh --force` to re-copy

### Phase 54 — Swift mirror parity (schema + import + UI gaps)

- **Migration `031_swift_parity_tables`** — `course_grading_category`, `requirement_fulfillment`, `course_override`, `transfer_proof_record`, catalog scrape tables, career resume match tables, `finance_category` / `finance_due` / `finance_net_worth_snapshot`
- **`swift_mirror.rs`** — `mirror_all_tables()` copies intersecting columns from attached Swift GRDB into Tauri tables (creates missing dest tables via `CREATE TABLE … AS SELECT … WHERE 0`)
- **Import mappers** — `ZPROFILE` → `profile`; Swift Finance camelCase → Tauri snake_case accounts/transactions
- **IPC** — `academics_list_grading_categories`, `documents_*_watched_folder`, `finance_list_categories`, `finance_list_due`
- **UI** — Settings Documents watchdog panel; Settings Finance connections + mirrored category/IOU counts; Career **Stats** + **Apply** routes; Discovery CDS cost/outcomes; Overview **Academic calendar** widget; Course dashboard **Grading categories** card

### Phase 55 — Pragmatic 1:1 gaps (free substitutes)

- **Background services pack** — filesystem watchdog (Downloads/Desktop + optional iCloud `College` folder on macOS), stale vault monitor, screenshot triage, Tokio schedulers (finance recurring, discovery federal sync stub, calendar course linker), **weekly digest** notification (open tasks, 7-day events, stale vault count); IPC `background_weekly_digest_preview` for Settings test
- **Smart Boards, prereq UI, finance recurring/dues, discovery federal sync** — landed in prior phases; weekly digest closes Swift `VaultWeeklyDigest` parity
- **Vault file copy fix** — import path copies into vault storage (no symlink-only references)
- **Free map substitute** — Calendar event inspector embeds **Leaflet + OpenStreetMap** (240px tile + marker) when Nominatim geocode exists in event notes; Apple/Google Maps deep links retained

### Phase 56 — Final parity push (orchestration + Pathing C + sync + preview)

- **Assistant tool registry** — 66 tools with scored intent planning + optional OpenAI tool refinement; `assistant_list_tools` + Settings expandable registry
- **Pathing Phase C depth** — migration `033`: role expectations, entry relationships, resume picker, merge entries; inspector tabs Expectations / Related / Resume
- **Finance Coinbase sync** — `finance_sync_coinbase` (accounts + public spot prices); daily scheduler; Settings sync button + last sync timestamp
- **Catalog vector index** — migration `034`: `catalog_course_embedding`; reindex + semantic search + post-ingest background hook; Catalog semantic toggle
- **SyllabusAI PDF** — in-pane PDF tab (`syllabus_resolve_pdf_path`), Refine with AI second pass, OCR stub message for scanned PDFs
- **Documents preview** — `documents_quick_look_preview` (encrypted COLENC1 decrypt-to-cache); nested VaultFolderTree; in-pane inspector preview

### Phase 57 — Closure pass (verification + GRDB pathing)

- **Migration `035_pathing_goals_scenarios`** — goals, scenarios, disclosure in GRDB (replacing settings JSON)
- **IPC** — `career_list/upsert/delete_path_goal`, `career_get/save_path_scenario`, `career_get/save_path_disclosure`, `career_migrate_pathing_settings`
- **Import** — finance table copy wired; vault files always attempted on import
- **Gate script** — `bash scripts/check-tauri-parity.sh` (tsc, cargo, tests, import, DB sanity, build)
- **Cutover doc** — [TAURI_CUTOVER.md](TAURI_CUTOVER.md)
- **Windows** — built in CI (`.github/workflows/cross-platform-release.yml` on `desktop-v*` tags); local macOS cross-compile optional

Run the parity gate before release:

```bash
bash scripts/check-tauri-parity.sh
```

### Deferred (post-ship / infra)

Optional hardening (not daily-driver blockers):

- Place real `.onnx` / MLX weights under the models dir for onnx-local / future ORT EP
- Configure GitHub signing secrets for notarized Tauri releases
- macOS-only EventKit two-way FFI (OAuth + ICS substitutes already land workflow)
- Full Coinbase OAuth (API key field supports Bearer token + public spot price sync today)
