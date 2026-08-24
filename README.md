# Blueprint (College Desktop)

Cross-platform desktop app for planning your degree, tracking applications, calendar, documents, and finance — built with **Tauri v2**, **React**, and **Rust**.

> Active development. Build from source; see [docs/DESKTOP_TAURI.md](docs/DESKTOP_TAURI.md).

## Stack

| Layer | Tech |
|-------|------|
| UI | React 19 + TypeScript + Tailwind + Framer Motion |
| Shell | Tauri v2 |
| Core | Rust + SQLite |
| Platforms | macOS + Windows |

Source lives in **`CollegeDesktop/`**.

## Develop

```bash
cd CollegeDesktop
bun install
bun run tauri:dev
```

From the repo root (after install):

```bash
bun run tauri:dev
```

## Build

```bash
cd CollegeDesktop && bun run tauri:build
```

Release CI: tag `desktop-v*` → `.github/workflows/cross-platform-release.yml`.

## Docs

- [DESKTOP_TAURI.md](docs/DESKTOP_TAURI.md) — architecture & module status
- [PATH_C_VISUAL_FIDELITY.md](docs/PATH_C_VISUAL_FIDELITY.md) — UI fidelity tracker
- [TAURI_CUTOVER.md](docs/TAURI_CUTOVER.md) — cutover / smoke checklist
- [UI_CATALOG.md](docs/UI_CATALOG.md) — design primitives

## License

MIT — see [LICENSE](LICENSE).
