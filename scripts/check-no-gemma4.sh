#!/usr/bin/env bash
# CI guard: Gemma 4 assistant model removed in favor of Qwen JSON worker.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_SRC="$ROOT/College"
TESTS_SRC="$ROOT/CollegeTests"

# Allow legacy purge keys in ModelMigrationService only.
if grep -rE 'ModelSpec\.gemma4|\.gemma4\b|GemmaAssistantSession|gemma-4-e4b|gemma-4-e2b' \
    "$APP_SRC" "$TESTS_SRC" 2>/dev/null \
    | grep -v 'ModelMigrationService.swift'; then
  echo "error: Gemma 4 symbols found in app/tests"
  exit 1
fi

echo "ok: no Gemma 4 symbols in College target sources"
