# ADR 010 — Sync: local-first ship posture (D-10)

**Status:** Accepted  
**Date:** 2026-06-23  
**Context:** Part 27 / M30-078 — marketing and roadmap referenced multi-device sync; no CloudKit (or equivalent) ship path exists today.

## Decision

**Ship as local-first.** Profile, planner, vault metadata, and career data remain on this Mac. Backup/export (`.colbk`) is the supported migration path between machines until a sync layer ships.

## Rationale

- Unified SwiftData store + Keychain master key are validated for backup/restore (`AppBackupRestoreStoreTests`).
- CloudKit schema, conflict resolution, and FERPA review for server-side student data are not implemented.
- Claiming "sync across devices" without infrastructure would violate production honesty (E-62–64).

## Consequences

- Settings and Privacy Overview must not imply automatic cloud sync.
- iCloud Calendar/Google Calendar integrations sync **calendar events only**, not the full College database.
- Future sync work requires a new ADR superseding this one with schema, encryption, and opt-in UX.

## Alternatives considered

1. **CloudKit private database** — deferred; needs conflict model + entitlement review.
2. **Remove backup** — rejected; backup is the current cross-machine story.
