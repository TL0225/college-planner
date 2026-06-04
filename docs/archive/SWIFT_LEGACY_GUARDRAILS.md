# Swift Legacy Guardrails

Date: 2026-04-27

These guardrails keep new legacy debt from accumulating after the audit.

## Recurring Re-Audit Cadence

- Run a full Swift inventory monthly.
- Run a full legacy/performance review quarterly.
- Re-run the dependency watchlist whenever SwiftPM dependencies change.
- Re-run the delete-candidate check before major releases.

## Compatibility Code Policy

Any new compatibility, legacy, fallback, or migration path must include:

- owner,
- reason,
- date introduced,
- expected removal condition,
- validation test or smoke path,
- whether it affects persisted user data.

Recommended comment format:

```swift
// Compatibility: <reason>
// Owner: <team/person>
// Added: YYYY-MM-DD
// Remove when: <condition>
// Validation: <test/smoke>
```

## Review Checklist

Before merging Swift changes, ask:

- Does this add another singleton/global mutable state path?
- Does this add work to the main actor that could touch IO, network, parsing, or large collections?
- Does this duplicate an existing scraper, auth provider, coordinator, or persistence path?
- Does this create a new fallback without a removal condition?
- Does this introduce `@unchecked Sendable` or `nonisolated(unsafe)`?
- Does this grow an already large file instead of extracting a focused unit?

## Thresholds

- Files over 1000 lines require an extraction note or explicit acceptance.
- New compatibility paths require owner/removal criteria.
- New UI tests should prefer predicate waits over fixed sleeps.
- New Core Data hot paths should avoid per-item fetches inside loops.
- New dependency pins should prefer stable tags/revisions over branch pins.

## Drift Controls

- Track `SWIFT_FILE_AUDIT_INDEX.csv` count changes.
- Track new files with `legacy`, `old`, `deprecated`, `backup`, or `compat` in names/comments.
- Track new `shared` singleton declarations.
- Track new synchronous `Data(contentsOf:)` usage in app code.
- Track new `Thread.sleep` usage in tests.

