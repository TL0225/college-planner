#!/usr/bin/env bash
# End-to-end parity gate for the Tauri desktop app (Phases 53–56+).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> TypeScript"
npx tsc --noEmit

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

echo "==> Swift workspace import"
bash scripts/import-swift-workspace.sh --force | tail -20

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
npm run build

echo ""
echo "OK — Tauri parity gate passed."
