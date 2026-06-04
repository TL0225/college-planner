# Calendar FFI / recurrence / ICS

## Deployment target

- **Current:** macOS 26.4 (`MACOSX_DEPLOYMENT_TARGET` in `College.xcodeproj`) — universal binary, Tahoe-aligned.
- **Roadmap option:** macOS 27+ arm64-only when Intel support is no longer required.

## RRULE expansion (Phase 2d)

| Path | Library | Status |
|------|---------|--------|
| **Swift (v1)** | [RRuleSwift](https://github.com/teambition/RRuleSwift) | Default for non-Apple providers until Rust path is ready |
| **Rust + UniFFI** | `ical` crate + UniFFI Swift bindings | Optional; shared with ICS parser (Phase 4) |

**Decision (Phase 0):** Ship **RRuleSwift** for Google/Outlook/iCloud recurrence expansion. Apple-mapped events use **EventKit** `events(matching:)` for expanded occurrences (Option B in redesign plan).

## ICS parser (Phase 4)

| Path | Notes |
|------|-------|
| Swift | Initial parser in `College/Calendar/ICS/` |
| Rust `ical` + UniFFI | `cargo build --target aarch64-apple-darwin` when arm64-only |

## Build (Rust path — future)

```bash
cd rust-calendar-ffi
cargo build --release --target aarch64-apple-darwin
```

UniFFI generates Swift bindings into `CollegePlatform/Sources/CollegePlatform/FFI/`.

## EventKit concurrency

- `AppleCalendarProvider` is an **`actor`**; all `EKEventStore` work runs on the provider executor.
- Do not call `EKEventStore` from `@MainActor` UI code.
