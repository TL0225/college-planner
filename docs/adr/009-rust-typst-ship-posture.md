# ADR 009 — Rust Typst ship posture (RS1)

**Status:** Accepted  
**Date:** 2026-06-16  

## Decision

CI **documents** Typst bridge posture: Release builds without `COLLEGE_TYPST_LINKED` use CoreText fallback (`CollegeTypst.swift` assertion in debug only). PR CI runs Release compile; optional `rust-typst` job is manual until bridge is in default build graph.

## Verification

- `release-hardening.yml` — hardened runtime + entitlements
- `app-ship-gates.yml` — Release `xcodebuild build`
- Local: link Rust typst per `College/Rust/` README when testing PDF export
