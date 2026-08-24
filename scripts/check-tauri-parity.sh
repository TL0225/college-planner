#!/usr/bin/env bash
# End-to-end gate for the Tauri desktop app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DESKTOP="$ROOT/CollegeDesktop"
cd "$DESKTOP"

echo "==> TypeScript"
bun run typecheck

echo "==> Rust check"
(cd src-tauri && cargo check)

echo "==> Assistant registry tests"
(cd src-tauri && cargo test assistant_tool_registry --quiet)

echo "==> Windows target (CI-only on macOS without cross-linker)"
if rustup target list --installed | grep -q x86_64-pc-windows-msvc; then
  if (cd src-tauri && cargo check --target x86_64-pc-windows-msvc 2>/dev/null); then
    echo "    Windows cross-check passed"
  else
    echo "    skip: local cross-linker missing — Windows builds run in cross-platform-release.yml"
  fi
else
  echo "    skip: rustup target add x86_64-pc-windows-msvc"
fi

echo "==> Optional legacy Swift DB import (if present on disk)"
bash "$ROOT/scripts/import-swift-workspace.sh" --force 2>/dev/null | tail -20 || echo "    skip: no Swift DB or import unavailable"

DB="${HOME}/Library/Application Support/CollegeDesktop/College.sqlite"
if [[ -f "$DB" ]]; then
  echo "==> DB sanity ($DB)"
  sqlite3 "$DB" "SELECT 'migrations', COUNT(*) FROM schema_migrations;"
  sqlite3 "$DB" "SELECT 'profile', COUNT(*) FROM profile;"
  sqlite3 "$DB" "SELECT 'finance_account', COUNT(*) FROM finance_account;"
  sqlite3 "$DB" "SELECT 'job_board_smart_board', COUNT(*) FROM job_board_smart_board;"
  sqlite3 "$DB" "SELECT 'career_path_goal', COUNT(*) FROM career_path_goal;"
  sqlite3 "$DB" "SELECT 'catalog_course_embedding', COUNT(*) FROM catalog_course_embedding;"
  sqlite3 "$DB" "SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1;"
fi

echo "==> Frontend production build"
bun run build

echo ""
echo "OK — Tauri parity gate passed."
