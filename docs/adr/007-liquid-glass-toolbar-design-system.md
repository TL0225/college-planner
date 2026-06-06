# ADR 007: Liquid Glass Toolbar Design System

**Status:** Implemented (Tahoe glass layers 1–7; density v2 theme scaling; hover/press on all public controls)  
**Date:** 2026-06-05

## Context

`GlassToolbarControls.swift` is a control library with hardcoded materials (`regularMaterial`), scattered metrics (`GlassToolbarMetrics`), and ad-hoc interaction styling (`.opacity(isEnabled ? 1 : 0.55)`). macOS 26 Tahoe Liquid Glass requires motion, depth, interaction states, and replaceable styling—not capsule blur alone.

## Decision

The toolbar visual layer is a **replaceable design system** via the `GlassToolbarStyle` protocol. Feature `*ToolbarContent` files never set padding, materials, corner radii, or animations directly.

### Seven layers (build order)

| Layer | Module | Responsibility |
| --- | --- | --- |
| 1 | `ToolbarGlassTheme` | Static tokens: radii, spacing, materials, stroke, `minHitTarget` |
| 2 | `GlassMotionTokens` | Shared spring vocabulary: hover/press scale, elevation, transitions |
| 3 | `GlassInteractionState` | `idle`, `hover`, `focus`, `pressed`, `selected`, `disabled` |
| 4 | `ToolbarDensity` | `compact` / `regular` / `expanded` — v1 from sidebar visibility; **v2** scales all `ToolbarGlassTheme` metrics via `scaled(for:)` |
| 5 | `GlassToolbarStyle` | Protocol wiring theme + motion + interaction; `TahoeGlassStyle` default |
| 6 | Accessibility | Label, identifier, `minHitTarget` on every public control |
| 7 | `GlassToolbarControls` | Composed controls consuming style/environment only |

Module layout: `College/App/Toolbar/Glass/`.

### GlassToolbarStyle protocol

```swift
protocol GlassToolbarStyle {
    var theme: ToolbarGlassTheme { get }
    var motion: GlassMotionTokens { get }
    func material(for state: GlassInteractionState) -> Material
    func animation(for transition: GlassMotionTransition) -> Animation
}

struct TahoeGlassStyle: GlassToolbarStyle { ... }
// Future: struct macOS27GlassStyle: GlassToolbarStyle { ... }
```

Inject via `@Environment(\.glassToolbarStyle)` defaulting to `TahoeGlassStyle()`.

### GlassInteractiveSurface contract

Public glass controls **must not** apply interaction styling directly. All interactive chrome routes through `GlassInteractiveSurface`:

```swift
struct GlassInteractiveSurface<Content: View>: View {
    @Environment(\.glassToolbarStyle) private var style
    let content: Content
    // Drives idle/hover/focus/pressed/selected/disabled via GlassInteractionState
}
```

Enforced by `GlassInteractionCoverage` architecture test: public `*Button`, `*Field`, `*Menu*` bodies must reference `GlassInteractiveSurface`; no ad-hoc `.opacity(isEnabled` on chrome.

### Rejected

- Scattered `.padding(N)` / `.cornerRadius(N)` in feature toolbar content or controls
- Per-control custom `withAnimation` curves
- Private surface modifiers hardcoding `.regularMaterial` (surfaces come from `GlassToolbarStyle.material(for:)`)
- `ToolbarGlassButton` / NSToolbar-specific glass path

## Consequences

- **Positive:** Future OS material change = add `macOS27GlassStyle`, re-run visual tests—zero `*ToolbarContent` edits.
- **Positive:** Interaction and motion feel consistent across all toolbar controls.
- **Negative:** Phase 5b must follow layer build order; interaction + motion land before control refactor.
- **Follow-up:** `docs/liquid-glass-toolbar.md` for developer workflow and snapshot requirements.
