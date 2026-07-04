# ADR 008 — Encryption ship posture (SEC1)

**Status:** Accepted  
**Date:** 2026-06-16  
**Context:** Snow Leopard audit finding SEC1 — `SecurityManager.encryptionEnabled` hardcoded `false` while UI implies `.colenc` vault encryption.

## Decision

**Ship with encryption disabled** for the current release train. Sensitive vault files use `.colenc` extension naming but are stored with backup-key sealing only when encryption flag is off; the app auto-unlocks for backup/export operations.

## Rationale

- Encryption UX (unlock prompts, migration of legacy blobs) is not fully validated across vault import, LMS, and catalog paths.
- Backup/export already requires Keychain master key via `ensureBackupKeyIfNeeded()`.
- Enabling encryption without full `SecurityManager` + wipe + vault round-trip test coverage (T4) risks data loss.

## Consequences

- `SecurityManager.encryptionEnabled` remains `false` until T4 tests and user-facing copy are aligned.
- Privacy overview must state plaintext-at-rest posture accurately.
- Re-enable path: set storage flag, run `migrateSensitiveBlobsIfNeeded`, add `SecurityManagerTests` round-trip.

## Alternatives considered

1. **Remove crypto UI** — deferred; users expect lock screen for shared machines.
2. **Force encryption on** — rejected without test harness (Snow Leopard V&V Phase 1).
