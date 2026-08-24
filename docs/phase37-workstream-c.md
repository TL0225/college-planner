# Phase 37 Workstream C — Career openings URL import + Resume DnD

Cross-platform Tauri deliverables closing two Career gaps without Swift edits.

## 1. Job posting import from URL

### Rust (`src-tauri/src/commands/career.rs`)

- **`career_import_job_from_url(url: String)`** — async Tauri command
  - Fetches HTML via shared `scrapers::fetch_html` (polite reqwest client)
  - Heuristic extraction:
    - `<title>` → role title (strips common board suffixes and `" at Company"` patterns)
    - `og:site_name` / `application-name` meta → company; falls back to registrable domain label
    - `description` / `og:description` meta → snippet stored in `raw_json.description`
  - Upserts `workday_job_posting` by normalized URL (update if URL already exists)
  - Returns posting id; bumps `career` revision for live query refresh

### Frontend (`src/modules/career/CareerModule.tsx`)

- Openings toolbar: **Import from URL** (secondary) + **Add opening** (primary)
- Modal with URL field → `ipc.careerImportJobFromUrl` → selects imported posting on success

### IPC

- `src/lib/ipc.ts` — `careerImportJobFromUrl`
- `src-tauri/src/lib.rs` — command registered in invoke handler

## 2. Resume section reorder DnD

### `ResumeLiveBuilder.tsx`

- Sidebar section chips are **draggable** (HTML5 DnD) to reorder `sectionOrder` on the draft
- Order persisted in settings key `career.resumeLiveDraft` JSON (`sectionOrder` array)
- Export builders (`buildResumeMarkdown`, `buildResumeTypst`) honor `sectionOrder` for body sections (header/contact/tailoring always first)

### Defaults

Sidebar/export order (when brag book enabled):

`header → experience → education → skills → projects → brag`

## Verification

```bash
npx tsc --noEmit
cd src-tauri && cargo check
```

## Follow-ups (out of scope)

- Full ATS/Workday structured scrape (JSON-LD, Greenhouse API)
- Auto-save section order on every drag (today: included in **Save draft**)
- Location extraction from posting HTML
