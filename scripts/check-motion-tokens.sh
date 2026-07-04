#!/usr/bin/env bash
# M30-052 — forbid raw UIKit-style spring animations outside motion tokens.
set -euo pipefail
cd "$(dirname "$0")/.."

SCAN_DIR="College"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

rg -n '\.animation\(\.spring\(' "$SCAN_DIR" --glob '*.swift' >"$TMP" || true

violations=0
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  file="${line%%:*}"
  rel="${file#./}"
  source="$(<"$file")"
  if [[ "$source" == *"motionReduced"* || "$source" == *"reduceMotion"* || "$source" == *"CollegeMotion"* || "$source" == *"DesignSystem.Motion"* ]]; then
    continue
  fi
  echo "error: raw spring animation without motion gate — $line"
  violations=$((violations + 1))
done < "$TMP"

echo "motion-tokens gate: $violations violation(s)"
if [[ "$violations" -gt 0 ]]; then
  exit 1
fi
echo "ok: motion token parity PASS"
