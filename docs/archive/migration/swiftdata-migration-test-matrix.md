# local store migration test matrix (Phase 7g)

Tracks test coverage for the local store → local store cutover. Update as new integration tests land.

## CI gates

```bash
./scripts/check-neutral-persistence-labels.sh
xcodebuild test -scheme College -destination 'platform=macOS' -only-testing:CollegeTests
```

| Gate | Target |
|------|--------|
| `check-neutral-persistence-labels.sh` | Zero banned persistence labels in `College/` + `CollegeTests/` |
| `CollegeTests` | All enabled tests green (currently **287** run, **10** skipped) |

## Infrastructure (done)

| File | Status |
|------|--------|
| `CollegeTests/local store/PersistenceTestHarness.swift` | Done |
| `CollegeTests/local store/PersistenceFixtureFactory.swift` | Done |
| `CollegeTests/local store/PersistenceTestCase.swift` | Done — uses `AppDataStore.shared.profileContext` |

## Entity smoke (partial)

| Area | Test class | Status |
|------|------------|--------|
| Profile / planner | `ProfilePlannerModelsStoreTests`, `ProfilePartitionEntitySmokeTests` | Done |
| Catalog | `CatalogModelsStoreTests`, `CatalogPartitionEntitySmokeTests` | Done |
| Calendar / vault / career repos | `*Repositorylocal storeTests`, `*ReadBridgeTests`, `*SyncBridgeTests` | Done |

## Ported existing tests

Most `CollegeTests` run on local store via `CollegePersistence` / harness. Bridge tests under `CollegeTests/local store/` cover read paths formerly backed by local store.

**Skipped (intentional):** live network, PDF fixture env, catalog-catoid follow-ups — see test source `XCTSkip` messages.

## Integration gaps (open)

| Test class (planned) | Validates | Status |
|----------------------|-----------|--------|
| `DataWipeStoreTests` | On-disk store erase | Done |
| `AcademicsAuditSnapshotStoreTests` | `AuditSnapshotStore` + batch catalog lookup | Done |
| `CatalogBackgroundSyncStoreTests` | Off-main ingest, streamed PDF path | Done |
| `CalendarSearchStoreTests` | Background fetch + publish | Done |
| `AppBackupRestoreStoreTests` | Profile + catalog school list round-trip | Done |
| `LaunchSingleCatalogMmapTests` | One active catalog container at launch | Done |
| `SchemaMigrationPlanTests` | Versioned schema bump | Done |

## UI / E2E

| Target | Status |
|--------|--------|
| `UITestPersistenceSeeder` | Present |
| `UITestlocal storeSeeder` | Removed (Jun 2026) |
| Full `CollegeUITests` smoke | Manual / periodic |

## Post-migration UI (in progress)

Profile tab views (`ProfileView`, achievements, experiences, per-degree editors) are being re-wired to local store-only repositories by a parallel effort. Automated repo/bridge tests above are green; use [`docs/post-migration-ui-checklist.md`](post-migration-ui-checklist.md) for manual UI sign-off once that work lands.

## Manual sign-off checklist

1. Cold launch after deleting sqlite stores (see the fresh-cutover checklist in docs)
2. Catalog sync → Academics audit → backup → wipe
3. School switch closes prior catalog container
4. Instruments: launch RSS without LLM tab; no duplicate Brightspace WKWebView preload
5. Post-migration UI flows (profile edit, achievements, experiences) — see `docs/post-migration-ui-checklist.md`
