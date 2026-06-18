# Development Guide

For what Blueprint is, see the [README](../README.md). For every tracked file's purpose, see [REPOSITORY.md](REPOSITORY.md).

---

## Requirements

- macOS 15+ on Apple Silicon (`arm64`)
- Xcode 16+ with Swift 6
- Rust toolchain (optional) for Typst-linked resume PDF generation — see [Rust / Typst](#rust--typst)

## Clone and build

1. Clone the repository.
2. Copy secrets (local only, never commit):
   ```bash
   cp Secrets.xcconfig.example Secrets.xcconfig
   ```
   Edit `MICROSOFT_CLIENT_ID` and other keys as needed. `Config.xcconfig` includes `Secrets.xcconfig`.
3. Open `College.xcodeproj` and build scheme **College** (Release or Debug).

`College.xcodeproj` is tracked in git for CI and fresh clones. Per-user Xcode state (`*.xcuserdata`) is gitignored.

### Swift packages

```bash
cd Packages/CollegeCalendar && swift test
cd Packages/CollegePlatform && swift test
```

## Test tiers

| Tier | When | Command |
|------|------|---------|
| **A — PR ship gates** | Every push/PR | `.github/workflows/app-ship-gates.yml` |
| **B — Unit shard** | PR + local | `bash scripts/run-college-unit-tests.sh` |
| **C — Catalog** | PR | `bash scripts/run_catalog_tests.sh` |
| **D — Nightly** | Scheduled | `.github/workflows/snow-leopard-nightly.yml` |

Full `CollegeTests` (168+ files) runs via the unit-test shard script on PR CI.

## Rust / Typst

Release resume PDF generation expects `COLLEGE_TYPST_LINKED` when the Rust typst bridge is built. CI documents fallback posture in [adr/009-rust-typst-ship-posture.md](adr/009-rust-typst-ship-posture.md). Local build:

```bash
# See rust-typst/ for bridge sources
cd rust-typst && ./build_macos.sh
```

## Encryption (SEC1)

At-rest field encryption is **disabled for current releases** (`SecurityManager.encryptionEnabled` returns `false`). Backups still use Keychain-backed AES-GCM. See [adr/008-encryption-ship-posture.md](adr/008-encryption-ship-posture.md).

## Diagnostics

Settings → Performance & Diagnostics; export bundle includes crash reports and performance health metrics when enabled.

## Related docs

- [Architecture](ARCHITECTURE.md) — module layout and data flow
- [Repository guide](REPOSITORY.md) — purpose of every tracked file
- [ADRs](adr/) — architecture decision records
