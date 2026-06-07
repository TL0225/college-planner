# Liquid Glass Toolbar

Developer guide for native macOS 26 Liquid Glass in the main window toolbar.

## Rules

### 1. Native APIs only

Use Apple's Liquid Glass APIs directly in `App/Toolbar/**` — no custom wrapper module.

| Pattern | API |
| --- | --- |
| Icon toolbar button | `.buttonStyle(.glass)` |
| Multiple glass shapes | `GlassEffectContainer(spacing:) { … }` |
| Layout | `ToolbarMetrics.iconControlSize`, `ToolbarMetrics.minHitTarget` |

### 2. Accessibility

Every toolbar control requires:

- `.accessibilityLabel(...)`
- `.accessibilityIdentifier(...)` — stable for UI tests (e.g. `"toolbar.calendar.next"`)
- `.frame(minWidth:minHeight:)` from `ToolbarMetrics.minHitTarget` (44pt)

### 3. Dispatch-only toolbar views

Toolbar chrome dispatches via `ToolbarDispatcher`; feature views register handlers and mutate `*SceneState`. Do not mutate scene state from toolbar views except via dispatch.

### 4. New controls

Add controls inline in `*ToolbarContent.swift` or `AppToolbarViews.swift` using native APIs. Add snapshot coverage in `ToolbarVisualTests` when visuals change.

## Record-mode workflow

Visual regression is a merge gate for toolbar chrome changes.

### Seed or update snapshots

```bash
bash scripts/record_toolbar_snapshots.sh
```

Or:

```bash
RECORD_SNAPSHOTS=1 xcodebuild test -scheme College -only-testing:CollegeTests/ToolbarVisualTests CODE_SIGNING_ALLOWED=NO
```

### PR requirements

1. Run record mode when changing toolbar chrome in `App/Toolbar/**`.
2. Commit snapshot artifacts under `CollegeTests/__Snapshots__/ToolbarVisual/`.
3. Include intentional snapshot diff in PR review.

### Snapshot matrix (minimum)

| Scenario | Validates |
| --- | --- |
| Light appearance | Calendar chrome legibility |
| Dark appearance | Calendar chrome legibility |

## Superseded custom stack

The former `College/App/Toolbar/Glass/` design system (ADR 007) was removed in favor of native APIs. See ADR 007 superseded note for history.
