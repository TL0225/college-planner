# Resize + Fullscreen UI Regression Checklist

Run this checklist for macOS UI changes that touch window chrome, sidebar, toolbar, or page layout.

## Window States

- Launch in windowed mode and verify traffic lights remain visible.
- Enter fullscreen, then exit fullscreen, and verify window returns to a resizable state.
- Maximize/zoom window, then restore, and verify titlebar controls and toolbar remain responsive.

## Resize Extremes

- Shrink to minimum size and verify assistant composer remains visible.
- Shrink height aggressively and verify sidebar footer controls remain visible.
- Shrink width aggressively and verify toolbar keeps profile/settings controls visible.

## Page Coverage

- Test Assistant page: header is top-safe-area anchored, transcript scrolls as the only flexible region, composer stays pinned to bottom-safe-area.
- Test Overview and Documents pages: toolbar items remain present after repeated resizes.
- Test Settings/Profile access: both controls are reachable (sidebar and toolbar routes).

## Transition Stress

- Resize rapidly while switching pages (Overview, Calendar, Assistant, Profile).
- Enter and exit fullscreen on each of those pages.
- Confirm no lost controls, clipped bottom content, or inaccessible navigation.
- On Assistant specifically, confirm top/bottom shell anchoring remains stable after fullscreen exit (no header/sidebar drift, no composer clipping).
