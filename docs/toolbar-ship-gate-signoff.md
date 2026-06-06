# Toolbar Refactor — Ship Gate Sign-Off

**Date:** 2026-06-05  
**Owner:** Timothy Leung  
**ADR 004 Phase 2 kickoff deadline:** 2026-06-19 (14 calendar days after toolbar refactor PR merge)

## Automated gates (passed)

| Check | Command / artifact | Status |
| --- | --- | --- |
| Release build | `xcodebuild -scheme College -configuration Release build CODE_SIGNING_ALLOWED=NO` | Pass |
| Architecture tests | `bash scripts/run_toolbar_tests.sh` | Pass |
| Forbidden symbols | `ToolbarArchitectureTests.testForbiddenSymbols` | Pass |
| Dispatcher lifecycle | `testDispatcherLifecycle`, `testDispatcherConcurrency`, `testDispatcherReplacement` | Pass |
| Tab-cycle stress (10×) | `ToolbarArchitectureTests.testDispatcherTabCycleStress` | Pass |
| Web dispatch routing | `ToolbarArchitectureTests.testWebToolbarDispatchRouting` | Pass |
| AppContainer composition | `ToolbarArchitectureTests.testAppContainerCompositionRoot` | Pass |
| Provider registry | `ToolbarArchitectureTests.testToolbarProviderRegistryExists` | Pass |
| Scene state (no *ToolbarState) | `ToolbarArchitectureTests.testNoSiblingToolbarObservableStores` | Pass |
| Visual regression | `ToolbarVisualTests` + `CollegeTests/__Snapshots__/ToolbarVisual/` | Pass |
| Glass accessibility | `GlassToolbarAccessibilityTests` | Pass |
| Health check | `bash scripts/toolbar-health-check.sh` | Pass (within thresholds) |
| Cross-feature imports | `bash scripts/check-feature-imports.sh warn` | Warn-only (2 existing Calendar → CollegePlatform) |

## Manual verification

### 10× tab smoke

Run the app locally and cycle **Calendar → Academics → Career → Web shortcut** at least 10 times. Confirm:

- Toolbar chrome swaps per page (`CalendarToolbarContent`, `AcademicsToolbarContent`, etc.)
- Calendar: header date, view mode picker, right sidebar toggle + panel menu
- Academics: stats sidebar toggle
- Career: segmented view picker + add/copy actions
- Web: back / forward / reload cluster

### Instruments leak pass (recommended at PR review)

1. Open **Instruments → Leaks** against a Debug build.
2. Cycle the same tabs 10× while watching live memory.
3. Confirm `ToolbarDispatcher` handler dictionary returns to zero after each view disappears (no growth across cycles).

Automated `testDispatcherTabCycleStress` covers handler registration churn; Instruments remains the manual confirmation for retained SwiftUI/AppKit objects.

## Phase 2 clock

- **ADR 004 owner:** Timothy Leung
- **Kickoff trigger:** Toolbar refactor PR merge to `main`
- **Hard deadline:** 2026-06-19 — `check-feature-imports.sh` flips warn → fail; begin Calendar package extraction

## PR checklist snippet

```markdown
## Toolbar ship gate
- [x] Release build + `scripts/run_toolbar_tests.sh`
- [x] Snapshot baselines committed
- [x] ADR 004 owner named (Timothy Leung); Phase 2 deadline 2026-06-19
- [ ] Manual 10× tab smoke (reviewer or author)
- [ ] Instruments Leaks pass (reviewer or author)
```
