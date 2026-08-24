# Tauri primary cutover checklist

Use this when **College Desktop (Tauri)** becomes your daily driver instead of (or alongside) the native Swift macOS app.

The Swift app remains supported. Tauri uses a **separate data root** and one-way import from Swift — not a shared live database.

---

## Before you switch

### 1. Data

- [ ] **Export Swift backup** (optional safety): Swift app → Settings → backup, or copy  
  `~/Library/Application Support/College.sqlite` and `CollegeFinance/Finance.sqlite`
- [ ] **Import into Tauri** (automatic on first launch if Tauri DB is empty, or force re-copy):

  ```bash
  bash scripts/import-swift-workspace.sh --force
  ```

- [ ] Confirm Tauri store: `~/Library/Application Support/CollegeDesktop/College.sqlite`
- [ ] Confirm vault files copied (Documents module shows your syllabi/PDFs)

### 2. AI / Assistant

- [ ] Configure **Ollama** or OpenAI-compatible endpoint in Settings → Assistant  
  (local hash/onnx fallback works without models; quality improves with Ollama or `.onnx` in `models/`)
- [ ] Optional: Settings → Assistant → expand **Tool registry** to verify 66 tools

### 3. Calendar

- [ ] Add Google/Outlook OAuth client IDs in Settings → Calendar (if you use cloud sync)
- [ ] Publish ICS feed or use **Push local events to cloud** (EventKit substitute)
- [ ] macOS: **Open in Calendar.app** handoff still available for Apple Calendar users

### 4. Finance

- [ ] Re-import Swift finance data via workspace import (mirror + Finance.sqlite)
- [ ] Optional: Settings → Finance → Coinbase API key → **Sync Coinbase now**
- [ ] Set up recurring rules under Finance → Accounts

### 5. Documents

- [ ] Settings → Documents → add watched folders (defaults: Downloads + Desktop)
- [ ] Verify watchdog status shows **Active** after app restart
- [ ] Encrypted Swift vault files: unlock app security store before preview

### 6. Catalog / Discovery

- [ ] Settings → Catalog → **Reindex embeddings** (enables semantic search)
- [ ] Settings → Discovery → optional College Scorecard API key → **Sync federal data**

### 7. Career

- [ ] Career → Sync boards (company URLs)
- [ ] Configure USAJobs / Built In credentials in Settings → Career if used
- [ ] Pathing: set **Resume** on each active path entry; review **Expectations** / **Related**

---

## Platform notes

| Capability | Tauri approach |
|------------|----------------|
| Maps | Leaflet + OpenStreetMap embed; Apple/Google deep links |
| Calendar native | OAuth + ICS; not EventKit two-way |
| Local AI | Ollama / OpenAI-compat; optional ONNX in `models/` |
| Updates | Tauri updater (Settings → Check for updates) |
| Windows | Same codebase; run `npm run tauri:build` on Windows or CI tag `desktop-v*` |

---

## Smoke test (30 min)

1. **Overview** — widgets load, week ahead populated  
2. **Planner** — drag requirement to term; open **Course dashboard** (prerequisites + grading)  
3. **Calendar** — create event with location → map tile appears  
4. **Documents** — folder tree, preview pane, watchdog last-file chip  
5. **Career** — Smart Board filter; Pathing Expectations tab  
6. **Assistant** — ask “what’s my GPA?” → tool loop runs  
7. **Syllabus AI** — PDF tab + Refine  
8. **Settings** — all 11 sections reachable  

---

## Rollback

- Keep Swift app installed; data is not deleted by Tauri import  
- Tauri data lives only under `CollegeDesktop/`  
- To reset Tauri: quit app, remove `~/Library/Application Support/CollegeDesktop/`, re-import  

---

## Release / CI

- Tag `desktop-v0.1.0` (or similar) triggers `.github/workflows/cross-platform-release.yml`
- Set signing secrets for notarized macOS + signed Windows (optional; unsigned draft artifacts when unset)
- macOS local release: `npm run tauri:build` (requires `default-run = "college"` in `src-tauri/Cargo.toml`)
- **Pre-release gate:** `bash scripts/check-tauri-parity.sh`

## Verification checklist (agent / CI)

- [ ] `bash scripts/check-tauri-parity.sh` exits 0
- [ ] `npm run tauri:dev` — Settings → Documents watchdog **Active**
- [ ] Career → Pathing → Expectations / Related / Resume tabs persist after restart
- [ ] Settings → Catalog → Reindex → Catalog semantic search works
- [ ] `bash scripts/import-swift-workspace.sh --force` — finance rows > 0 if Swift Finance DB exists

---

## Dual-app policy

| Use Swift when… | Use Tauri when… |
|-----------------|-----------------|
| MLX Metal / Apple FM quality matters | You need **Windows** or one cross-platform codebase |
| EventKit / MapKit native depth | Background watchdog + cross-platform sync substitutes are enough |
| Production Sparkle channel today | Tauri updater + GitHub releases |

Both apps can run on the same Mac with separate stores. Re-run import when you want Swift data refreshed in Tauri.
