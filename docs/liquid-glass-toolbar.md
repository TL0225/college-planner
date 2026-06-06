# Liquid Glass Toolbar

Developer guide for the Tahoe Liquid Glass toolbar design system. See ADR 007 for architecture.

## Rules

### 1. No magic numbers

All visual constants read from `GlassToolbarStyle` / `ToolbarGlassTheme` tokens. Controls use `style.theme.circleControlSize`, `style.theme.searchFieldWidth`, etc.—never hardcoded `.padding(8)` or `.cornerRadius(12)` in controls or `*ToolbarContent`.

### 2. Interaction states

All controls use `GlassInteractionState` for `idle`, `hover`, `focus`, `pressed`, `selected`, and `disabled`. Route interactive chrome through `GlassInteractiveSurface`; do not apply `.opacity` or `.scale` directly on public controls.

### 3. Motion tokens

All controls animate via `GlassMotionTokens` from the active `GlassToolbarStyle`. No one-off `withAnimation` curves or per-control spring definitions.

### 4. Density

Controls respect `@Environment(\.toolbarDensity)` or injected `ToolbarDensity`. v1 derivation: sidebar open → `.expanded`, collapsed → `.compact`, default → `.regular`.

### 5. New controls

New glass control → add to `GlassToolbarControls.swift` (under `Toolbar/Glass/`) + add snapshot coverage in `ToolbarVisualTests`.

### 6. Accessibility

Every public control requires:

- `.accessibilityLabel(...)` — required parameter or derived from `tip`
- `.accessibilityIdentifier(...)` — stable for UI tests (e.g. `"toolbar.calendar.next"`)
- `frame(minWidth:minHeight:)` from `theme.minHitTarget` (typically 44pt)

## Record-mode workflow

Visual regression is a **hard merge gate** for toolbar glass changes. Baselines must exist before the toolbar refactor PR merges.

### Seed or update snapshots

```bash
bash scripts/record_toolbar_snapshots.sh
```

### PR requirements

1. Run record mode locally when changing `College/App/Toolbar/Glass/**` or `GlassToolbarControls.swift`.
2. Commit snapshot artifacts (e.g. `CollegeTests/__Snapshots__/ToolbarVisual/`).
3. Include intentional snapshot diff in PR with screenshot review.
4. CI runs visual tests on PR—failures block merge.

### Snapshot matrix (minimum)

| Scenario | Validates |
| --- | --- |
| Light / dark appearance | Material and stroke legibility |
| Vibrant window / wallpaper | Glass legibility |
| Fullscreen | Density + placement |
| Sidebar open | `ToolbarDensity.expanded` |
| Sidebar closed | `ToolbarDensity.compact` |

## Future style swaps

When Apple ships new materials (e.g. macOS 27):

1. Add `macOS27GlassStyle: GlassToolbarStyle` in `College/App/Toolbar/Glass/`.
2. Swap default in `GlassToolbarEnvironment` or feature-flag.
3. Re-run `ToolbarVisualTests` in record mode; review diff.
4. Zero edits to `*ToolbarContent` files.
