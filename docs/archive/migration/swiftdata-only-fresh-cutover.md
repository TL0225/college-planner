# local store-only fresh cutover (no local store)

**Policy (2026-06-01):** local store is the only persistence layer. No read bridges fall back to local store. No dual-write to local store. Users may delete legacy SQLite stores and run a clean build.

This supersedes the interim “local store authoritative + mirror” notes in Phase 7c/7d.

---

## What “100% migration” means

| Layer | Target state |
|-------|----------------|
| **Writes** | All domains use `AppDataStore` + repositories (`ProfileRepository`, `CatalogRepository`, `CalendarRepository`, `VaultRepository`, `CareerRepository`). |
| **Reads** | UI and services read local store only. Delete `*ReadBridge` local store fallbacks and `ProfilePlannerSyncBridge` CD→SD sync. |
| **Ingest** | `importSchoolCatalog` and catalog scrape paths write local store catalog + profile containers directly (not `persistence coordinator`). |
| **App shell** | Remove `persistence coordinator`, `PersistenceController`, `@Environment(\.managedObjectContext)`, `CollegeDataModel.legacy data model bundle`. |
| **Gate** | `scripts/check-neutral-persistence-labels.sh` passes with zero matches (strict CI). |

**Status (2026-06-03):** Neutral persistence label gate passes (zero banned symbols in app/test sources). Debug macOS build and `CollegeTests` are green — **287 run, 10 skipped, 0 failures**. Test matrix: migration test matrix doc in docs. Optional follow-ups: re-enable skipped catalog-catoid / ingest-freshness tests; live-network and PDF fixture suites when env vars are set.

### MLX package macros (one-time in Xcode)

If the issue navigator shows *“Macro MLXHuggingFaceMacros must be enabled”* for `mlx-swift-lm`, trust it once: **File → Packages → Trust & Enable All Package Macros** (or the trust banner on first build). This is an Xcode editor/SPM approval step, not an app compile error.

---

## Fresh install: delete these stores

After pulling a local store-only build, quit the app and remove:

### local store (legacy — delete)

- `~/Library/Application Support/CollegeDataModel.sqlite` (+ `-wal`, `-shm`)
- `~/Library/Application Support/College/CollegeDataModel.sqlite` (+ companions)
- `~/Library/Application Support/CollegeProfile.sqlite` (+ companions) — legacy CD profile split
- `~/Library/Application Support/CollegeCatalog.sqlite` (+ companions) — legacy CD catalog split
- `~/Library/Containers/<app-bundle-id>/Data/Library/Application Support/` — same filenames if sandboxed

### local store (optional reset for truly empty state)

- `~/Library/Application Support/CollegeProfile-local store.sqlite` (+ companions)
- `~/Library/Application Support/College/catalog-stores/<schoolID>/catalog app-database.sqlite` (+ companions; on-disk basename unchanged from migration)

Then rebuild and run. First catalog scrape populates local store only (once ingest is ported).

---

## Execution order (same slices as 7f, stricter policy)

1. **Catalog ingest** — Port `importSchoolCatalog` → `CatalogSchoolImportService` (local store). Wire scrape runners and onboarding. Delete `persistence coordinator+Catalog*` extensions and `Cataloglocal storeMirror` (no mirror; single write path).
2. **Profile / planner / academics** — local store-only writes; remove `commitProfileEdits` CD saves and `ProfilePlannerStoreMirror`.
3. **Calendar** — `CalendarRepository` only; delete `CalendarReadBridge` CD path.
4. **Vault / career / overview** — Repositories only; remove entity types from UI.
5. **Teardown** — Delete legacy persistence folder, legacy data model bundle, framework link; enable strict neutral label gate.

Each slice: build + `CollegeTests` before the next.

---

## Interim vs target (do not confuse)

| | Interim (deprecated) | Target (this doc) |
|--|----------------------|-------------------|
| Catalog scrape | CD save → mirror to SD | SD save only |
| Program pickers | SD read → CD fallback | SD read only |
| Old scrapes | CD rows | N/A — delete sqlite |

---

## Progress tracking

```bash
scripts/check-neutral-persistence-labels.sh --report   # progress
scripts/check-neutral-persistence-labels.sh            # strict gate (must pass at end)
```
