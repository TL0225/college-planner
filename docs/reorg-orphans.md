# Reorg orphans and dead code inventory

Status as of **2026-06-09** (App Ship Refinement Wave 2–3). Paths below were verified orphans or Phase 7f shims and have been **removed from the target** or **relocated**.

## Deleted UI and chrome

| Path | Status | Notes |
|------|--------|-------|
| `College/App/AppHeaderView.swift` | **Deleted** | Orphan header chrome; shell uses native toolbar + sidebar |
| `College/Core/DesignSystem/AppNavBar.swift` | **Deleted** | Superseded by toolbar architecture |
| `College/Core/DesignSystem/LiquidGlassSidebarRow.swift` | **Deleted** | Sidebar rebuilt with native `List(selection:)` |
| `College/Features/Calendar/NewEventModal.swift` | **Deleted** | Unused modal; calendar uses inline add flow |
| `College/Features/Degree/DegreeView.swift` | **Deleted** | Unmounted route; Academics owns degree audit |
| `College/Features/Profile/AcademicIdentityView.swift` | **Deleted** | ~2.2k-line orphan; profile uses `IdentityCard` / `ProfileView` |

## Deleted Phase 7f store mirrors

| Path | Status | Notes |
|------|--------|-------|
| `College/Core/Data/Storage/ProfilePlannerStoreMirror.swift` | **Deleted** | No-op mirror; SwiftData is source of truth |
| `College/Core/Data/Storage/VaultStoreMirror.swift` | **Deleted** | No-op mirror |
| `College/Core/Data/Storage/JobBoardStoreMirror.swift` | **Deleted** | No-op mirror |

## Career reorg (relocated, not orphaned)

| Path | Status | Notes |
|------|--------|-------|
| `College/Features/Career/CareerWorkspaceView.swift` | **Moved** → `College/Features/Career/Workspace/CareerWorkspaceView.swift` | Workspace shell |
| `College/Features/Career/WorkdayScrapedData.swift` | **Deleted** | Types consolidated into Career models / scrapers |

## Archived audit docs (removed from tree)

The following lived under `docs/archive/` and were deleted during doc hygiene:

- `docs/archive/APP_PATH_MAP.md`
- `docs/archive/CFPreferencesFixPlan.md`
- `docs/archive/PDFImplementation.md`
- `docs/archive/SWIFT_63_MIGRATION_BASELINE.md`
- `docs/archive/SWIFT_AUDIT_*` (implementation roadmap, rubric, batch manifests, full audit report, legacy guardrails, risk register, performance bottleneck register, remediation progress/sequence)
- `docs/archive/SwiftAuditBatches/batch_01_manifest.md` … `batch_11_manifest.md`
- `docs/archive/migration/README.md`, `swiftdata-migration-7f-checklist.md`, `swiftdata-migration-test-matrix.md`, `swiftdata-only-fresh-cutover.md`

## Remaining candidates (confirm before action)

| Path | Status | Recommendation |
|------|--------|----------------|
| `College/Catalog/ONBOARDING_SCRAPE_AUDIT_NOTES.txt` | Dev notes (non-Swift) | Move to `docs/archive/` if still needed |
| `College/Data/local store/ProfilePlannerSyncBridge.swift` | No-op bridge | Delete with call-site cleanup when sync path is fully SwiftData-native |
| `CollegeTests/local store/ProfilePlannerSyncBridgeTests.swift` | Tests no-op bridge | Delete with bridge |

---

*Regenerate this file when deleting additional orphans; gate with `scripts/check-dead-code-manifest.sh`.*
