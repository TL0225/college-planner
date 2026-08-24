#!/usr/bin/env bash
# Copy Swift College.sqlite into the Tauri CollegeDesktop store (no Settings UI).
# Usage: bash scripts/import-swift-workspace.sh [--force]
set -euo pipefail
cd "$(dirname "$0")/.."
cargo run --quiet --manifest-path src-tauri/Cargo.toml --bin import_swift_workspace -- "$@"
