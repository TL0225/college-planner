#!/usr/bin/env bash
# CI guard: Features must not add new direct CollegePersistence access from Views.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FEATURES="$ROOT/College/Features"

# Allowlist grows only via explicit ADR exception — fail on net-new View files calling persistence.
VIOLATIONS=0
while IFS= read -r file; do
  if rg -n 'collegePersistence\.|CollegePersistence\.shared' "$file" >/dev/null 2>&1; then
    if rg -n 'struct .*View' "$file" >/dev/null 2>&1; then
      echo "warn: View file uses CollegePersistence directly: ${file#$ROOT/}"
      VIOLATIONS=$((VIOLATIONS + 1))
    fi
  fi
done < <(find "$FEATURES" -name '*.swift')

COUNT_FILE="$ROOT/build/view-persistence-count.txt"
mkdir -p "$ROOT/build"
echo "$VIOLATIONS" > "$COUNT_FILE"

# Gate: count must not exceed documented baseline (Phase 5 freeze).
BASELINE=120
if (( VIOLATIONS > BASELINE )); then
  echo "error: View→persistence direct calls ($VIOLATIONS) exceed baseline ($BASELINE)"
  exit 1
fi
echo "ok: View→persistence count $VIOLATIONS (baseline $BASELINE)"
