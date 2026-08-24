# CODEBASE_INDEX.md

**Living map for the Tauri desktop app.** Update when adding modules, IPC surfaces, or CI.

## Layout

| Path | Role |
|------|------|
| `CollegeDesktop/src/` | React UI (modules + design system) |
| `CollegeDesktop/src-tauri/` | Rust core (SQLite, IPC, scrapers, AI, security) |
| `workers/finance-link-proxy/` | Optional Cloudflare worker for finance OAuth |
| `scripts/check-tauri-parity.sh` | Typecheck + cargo + build gate |
| `scripts/import-swift-workspace.sh` | Optional one-way import from legacy Swift Application Support DB |

## Docs

- [DESKTOP_TAURI.md](DESKTOP_TAURI.md)
- [PATH_C_VISUAL_FIDELITY.md](PATH_C_VISUAL_FIDELITY.md)
- [TAURI_CUTOVER.md](TAURI_CUTOVER.md)
- [UI_CATALOG.md](UI_CATALOG.md)

## CI

- `.github/workflows/cross-platform-release.yml` — macOS + Windows Tauri builds on `desktop-v*` tags
- `.github/workflows/secret-scan.yml` — gitleaks

## Data roots

- Tauri: `~/Library/Application Support/CollegeDesktop/` (Windows: `%LocalAppData%\CollegeDesktop\`)
- Legacy Swift DB (import only): `~/Library/Application Support/College.sqlite`
