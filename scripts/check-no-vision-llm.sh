#!/usr/bin/env bash
# CI guard: no multimodal vision paths in the on-device LLM stack.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_SRC="$ROOT/College"
TESTS_SRC="$ROOT/CollegeTests"

# Allow migration strip helpers in ModelMigrationService only.
if grep -rE 'generateJSONWithOptionalImages|visionImageURL|maxVisionImages|copyImageForVision|appendVisionURL' \
    "$APP_SRC" "$TESTS_SRC" 2>/dev/null \
    | grep -v 'ModelMigrationService.swift'; then
  echo "error: vision LLM symbols found in app/tests (Phase 1b deletion)"
  exit 1
fi

echo "ok: no vision LLM symbols in College target sources"
