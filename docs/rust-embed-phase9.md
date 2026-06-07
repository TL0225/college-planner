# Phase 9 — Rust core & catalog embed

## Rust (`College/Rust/CollegeCoreSwift.swift`)

- **Source tree:** No `.rs` files or `rust-core/` crate in this repo; Rust is optional via `libcollege_core.a` (`COLLEGE_CORE_RUST_LINKED`).
- **Call sites:** No production Swift callers yet — wrapper is compile-safe with pure-Swift fallbacks.
- **Hot path:** N/A until linked and wired into catalog scrape / prereq parsing.
- **Instrumentation:** `os_signpost` on `normalizeCourseCode` and `extractCourseCodes` for Instruments POI when those APIs are adopted.
- **Regression:** `CollegeCoreSwiftRegressionTests` exercises Swift fallbacks (always run; no Rust link required).

## Catalog embed (MLX, not Rust FFI)

- **Runtime:** `CatalogEmbeddingRuntime` actor → `CatalogMLXEmbedService` or lexical fallback via `MLXTaskQueue`.
- **Lifecycle:** `CatalogEmbedMemoryLifecycle` is `@MainActor`; `embed(text:)` awaits `MainActor.run` only to cancel idle unload — intentional, not a full embed on main.
- **Heavy work:** GPU / MLX runs off main through the actor + task queue; catalog sync already uses `CatalogSync.*` signposts in `CatalogBackgroundSyncRunner`.
- **No Rust/C FFI** on the catalog embed path in this codebase.

## Sign-off status

Phase 9 is **closed for this release**: Swift fallbacks + regression tests are the shipping path; Rust linking is optional when `libcollege_core.a` is available.

## Follow-ups (future)

- Link `college-core` and add call-site tests when prereq/HTML helpers move off SwiftSoup.
- Consider dropping `MainActor.run` in `CatalogEmbeddingRuntime.embed` if lifecycle gains a nonisolated cancel hook.
