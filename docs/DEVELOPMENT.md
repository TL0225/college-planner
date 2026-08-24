# Development

## Prerequisites

- Bun 1.4+
- Rust stable (`rustup`)
- macOS: Xcode Command Line Tools (for Tauri linking)
- Windows: WebView2

## Run

```bash
cd CollegeDesktop
bun install
bun run tauri:dev
```

## Checks

```bash
bash scripts/check-tauri-parity.sh
```

See [DESKTOP_TAURI.md](DESKTOP_TAURI.md) for architecture.
