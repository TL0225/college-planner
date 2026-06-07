# Reorg orphans and dead code (Phase 0 inventory)

Candidates for archive or deletion after confirmation. **No action taken in Phase 0.**

## Unmounted views

### `College/Profile/AcademicIdentityView.swift`

| Field | Detail |
|-------|--------|
| **Status** | Orphan — not referenced from navigation |
| **Evidence** | Grep for `AcademicIdentityView` under `College/` returns only the type definition in this file (~2.2k lines). Not mounted in `ProfileView`, `ContentView`, or sidebar routes. |
| **Overlap** | Profile tab uses `IdentityCard`, `ProfileView`, and related components instead. |
| **Recommendation** | Archive to `College/Archive/AcademicIdentityView.swift` (exclude from target) or delete after product sign-off. Salvage any unique logic before removal. |

## Dev / audit artifacts in source tree

### `College/Catalog/ONBOARDING_SCRAPE_AUDIT_NOTES.txt`

| Field | Detail |
|-------|--------|
| **Status** | Non-Swift dev notes — not compiled |
| **Purpose** | Onboarding catalog scrape audit session notes |
| **Recommendation** | Move to `docs/archive/` in Phase 6 per reorg plan |

## No-op sync bridge

### `College/Data/local store/ProfilePlannerSyncBridge.swift`

| Field | Detail |
|-------|--------|
| **Status** | Dead code — no-op retained for call-site compatibility |
| **Evidence** | `syncFromStoreIfNeeded` is empty aside from `_ = collegePersistence`. Plan Phase 1 targets **delete** bridge and call sites. |
| **Call sites** | `CourseSearchView.swift`, `ProfilePlannerStoreQueryHost.swift`, `OverviewStoreQueryHost.swift`, `CalendarStoreQueryHost.swift`, `CareerStoreQueryHost.swift` |
| **Tests** | `CollegeTests/local store/ProfilePlannerSyncBridgeTests.swift` — remove or repurpose when bridge deleted |
| **Recommendation** | Delete in Phase 1A with call-site cleanup |

## Related test-only legacy

| Path | Notes |
|------|-------|
| `CollegeTests/local store/ProfilePlannerSyncBridgeTests.swift` | Tests no-op bridge — delete with bridge |

---

*Generated Phase 0 — confirm with product before deleting `AcademicIdentityView`.*
