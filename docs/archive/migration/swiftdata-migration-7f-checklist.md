# Phase 7f — local store deletion checklist

**Goal:** Delete legacy persistence sources, legacy data model bundle, and zero legacy persistence imports in `College/` and `CollegeTests/`. Gate: `scripts/check-neutral-persistence-labels.sh` (strict mode).

**Baseline (2026-05-31, slice 1):**

| Metric | Count |
|--------|------:|
| Symbol match lines (`import local store`, `legacy persistent container`, `legacy managed object`, `legacy fetch request`, `legacy managed property`) | ~671 |
| Files with any CD symbol | ~158 |
| Files with `import local store` | ~154 |
| `College/local store/*.swift` | 15 |
| `CollegeDataModel.legacy data model bundle` | present |

**Current (2026-06-02):** strict gate **passes** — 0 symbol lines, 0 CD imports, `College/local store/` deleted, `legacy data model bundle` absent. Remaining: confirm `xcodebuild` + `CollegeTests` on current sources.

Run progress anytime:

```bash
scripts/check-neutral-persistence-labels.sh --report
```

---

## Current architecture

**Target policy (2026-06-01):** app-database-only. No legacy fallback reads, no dual-write, fresh SQLite acceptable. See the fresh-cutover checklist in docs.

**Still in repo:**

- **App facade:** `typealias persistence coordinator = CollegePersistence` (compile-time name only; no local store runtime).
- **local store spine:** `AppDataStore`, `CollegeSchemaV1`, repositories (`ProfileRepository`, `CatalogRepository`, `CalendarRepository`, `VaultRepository`, `CareerRepository`).

**Policy:** Delete local store entirely — no `#if false` stubs, no deprecation shims, no runtime fallback.

---

## Ordered deletion sequence

Work top-to-bottom. Each slice must: migrate writes → remove CD reads/fallbacks → delete CD-only files → build + `CollegeTests`.

### Slice 0 — Dead code & folder hygiene (partial)

| Action | Files | Status |
|--------|-------|--------|
| Delete unused `local storeCatalogRepository` | 1 | done — zero call sites; superseded by `CatalogRepository` |
| Move `StringNormalization.swift` out of `local store/` | 1 | done — moved to `Catalog/` (Foundation-only) |
| Move `Models.swift` (AppPage nav) out of `local store/` | 1 | done — `College/App/AppModels.swift` |
| Relocate entity extensions after profile write migration | 2 | done — `Profile/ProfileEntity+Extensions.swift`, `Academics/AcademicProfileEntity+Extensions.swift` |

### Slice 1 — Utilities with local store equivalents (~8 files)

| Module | Files | Blocker |
|--------|------:|---------|
| `Catalog/Ingest/local storeMergeCoalescer.swift` | 1 | done — inlined single `legacy managed objectContext.mergeChanges` in catalog finalize path; file deleted |
| `Catalog/Store/persistence coordinator+CatalogStore*.swift` | 2 | done — replaced with `CatalogStorePortableBridge` and `CatalogStoreSnapshotBridge`; extension files deleted |
| `Platform/BuildCompatibility.swift` | 1 | done — Foundation-only notifications |

### Slice 2 — Profile & planner writes (~20 files)

| Module | CD files | local store ready |
|--------|--------:|-----------------|
| `persistence coordinator+ProfileWIP` | 1 | `ProfileRepository` |
| `persistence coordinator+AcademicProfiles` | 1 | `AcademicProfile` @Model |
| `PrimaryAcademicProfileAccess` | 1 | partial |
| `persistence coordinator+GraduationPlan` | 1 | `GraduationPlanTerm` @Model |
| `Profile/*` | 5 | read bridges partial; profile/academic dual-write via `commitProfileEdits` / `commitPrimaryAcademicProfileEdits` (2026-05-30) |
| `Academics/*` | 11 | planner bridges |
| `ProfilePlannerSyncBridge` | 1 | remove after SD writes |

### Slice 3 — Calendar reads → writes (~24 files)

Remove `CalendarReadBridge` CD fallback; migrate `CalendarEventWritePipeline` and sync providers to `CalendarRepository`.

### Slice 4 — Catalog partition (~10 + manager extensions)

Migrate scrape/merge/purge to local store catalog container; delete `Cataloglocal storeMirror` and CD manager catalog extensions.
Progress: `saveMajors` core implementation extracted from `persistence coordinator.swift` into `Catalog/Store/persistence coordinator+CatalogPrograms.swift` (2026-05-31), with wrappers/prune logic already split. Department/program dual-write via `CatalogRepository+Writes`, `Cataloglocal storeMirror.syncDepartments` / `syncPrograms`, and post-save `local storeCataloglocal storeSync` (2026-06-01). UI program lists via `CatalogProgramReadBridge` (profile, onboarding; 2026-06-01).

### Slice 5 — Career domain (~28 files)

Migrate via `CareerRepository`; delete `persistence coordinator+Career` and `persistence coordinator+Workday`.

### Slice 6 — Vault, documents, security (~8 files)

`VaultRepository` + security wipe paths off CD stores.

| Item | Status |
|------|--------|
| Vault mirror + write-through (`VaultStoreMirror`, `commitVaultEdits`) | done |
| UI reads via `VaultReadBridge` (Documents, courses, overview, career resumes) | done |
| Extended SD fields: `customDisplayName`, `courseCodeLinked`, `lastOpenedAt`, `tags`, `source` | done (2026-05-31) |
| Remaining: intelligence fields, full UI off `VaultDocumentEntity`, security wipe | pending |

### Slice 7 — Overview widgets & app shell (~25 files)

Replace `@EnvironmentObject persistence coordinator` with `AppDataStore` revision tokens.

### Slice 8 — Core stack teardown (final)

1. `persistence coordinator.swift`
2. `PersistenceController.swift`
3. `AppBackupManager.swift` (reimplement for local store)
4. `CollegeDataModel.legacy data model bundle`
5. Remaining `College/local store/`
6. Remove local store framework link
7. Enable strict `check-neutral-persistence-labels.sh` in CI

---

## Files by domain (import local store)

| Domain | Files |
|--------|------:|
| Career | 28 |
| Calendar | 24 |
| local store | 12 |
| Overview | 13 |
| Intelligence | 12 |
| Academics | 11 |
| Catalog | 10 |
| local store bridges | 6 |
| Profile | 5 |
| App | 5 |
| Services | 3 |
| Platform | 3 |
| Degree | 3 |
| Data | 3 |
| Courses | 3 |
| Security | 2 |
| DesignSystem | 2 |
| Brightspace | 2 |
| CollegeTests (misc) | 4 |
| CollegeTests/local store | 6 |
| Misc | 2 |

---

## CI

`release-hardening.yml` runs `scripts/check-neutral-persistence-labels.sh --report` on push/PR until migration completes.
