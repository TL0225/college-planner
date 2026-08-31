#!/usr/bin/env bash
# One-way copy from a legacy native Swift College.sqlite (Application Support)
# into the Tauri CollegeDesktop store. Optional — only needed if migrating old data.
# Usage: bash scripts/import-swift-workspace.sh [--force]
set -euo pipefail
cd "$(dirname "$0")/../CollegeDesktop"
cargo run --quiet --manifest-path src-tauri/Cargo.toml --bin import_swift_workspace -- "$@"
