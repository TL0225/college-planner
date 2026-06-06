# ADR 006: Toolbar Deprecation Policy

**Status:** Accepted  
**Date:** 2026-06-05

## Context

Toolbar refactors introduce replacement APIs (`AppToolbarStore`, `ToolbarDispatcher`, `GlassToolbarStyle`, `*ToolbarContent`). Without a removal policy, deprecated wrappers accumulate as permanent `// TODO: remove` debt.

## Decision

All deprecated toolbar APIs **must be removed within two releases** of the release that introduced the deprecation.

### Requirements

1. Mark APIs with `@available(*, deprecated, message: "...")` and a named replacement.
2. Each deprecation PR must include:
   - ADR note or PR comment citing the replacement
   - Removal milestone (target release version or date within two releases)
3. **No** permanent compatibility shims or indefinite `// TODO: remove` wrappers.
4. CI and architecture tests must not reference deprecated symbols after the removal window.

### Examples

| Deprecated | Replacement | Remove by |
| --- | --- | --- |
| `AppToolbarCoordinator` | `AppToolbarStore` + `ToolbarDispatcher` | Next release after toolbar merge |
| `ToolbarGlassButton` (NSToolbar path) | `StaticToolbarGlassButton` + design system | Same release as NSToolbar deletion |
| `CalendarToolbarState` (sibling observable) | `CalendarSceneState.toolbarProjection` | Release after projection migration |

## Consequences

- **Positive:** Prevents dual-path maintenance beyond two release cycles.
- **Positive:** Forces explicit migration planning in deprecation PRs.
- **Negative:** Breaking changes require coordinated release notes; no indefinite grace period.
