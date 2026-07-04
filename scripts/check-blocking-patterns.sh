#!/usr/bin/env bash
# CI guard: forbid DispatchQueue.main.sync and Thread.sleep outside documented allowlists.
# Wave 4 removes these; mirrors and Vault materializer polling are temporarily allowlisted.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

SCAN_DIRS=(
  "$ROOT/College"
  "$ROOT/CollegeTests"
  "$ROOT/Packages"
)

ALLOWLIST=(
  College/Core/Data/Repositories/VaultSourceFileMaterializer.swift
)

is_allowlisted() {
  local rel="$1"
  local entry
  for entry in "${ALLOWLIST[@]}"; do
    [[ "$rel" == "$entry" ]] && return 0
  done
  return 1
}

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

PATTERN='DispatchQueue\.main\.sync|Thread\.sleep'

for dir in "${SCAN_DIRS[@]}"; do
  [[ -d "$dir" ]] || continue
  rg -n "$PATTERN" "$dir" --glob '*.swift' 2>/dev/null || true
done > "$TMP"

violations=0
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  file="${line%%:*}"
  rel="${file#"$ROOT/"}"
  if is_allowlisted "$rel"; then
    continue
  fi
  echo "error: blocking pattern outside allowlist — $line"
  violations=$((violations + 1))
done < "$TMP"

allowlisted_count=0
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  file="${line%%:*}"
  rel="${file#"$ROOT/"}"
  if is_allowlisted "$rel"; then
    allowlisted_count=$((allowlisted_count + 1))
  fi
done < "$TMP"

echo "blocking-pattern gate: $allowlisted_count allowlisted hit(s), $violations violation(s)"

if [[ "$violations" -gt 0 ]]; then
  exit 1
fi

echo "ok: no blocking patterns outside allowlist"
