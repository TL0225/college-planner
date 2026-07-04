#!/usr/bin/env bash
# CI guard: every College xcodebuild test invocation must cap parallel workers at 2.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
violations=0

fail() {
  echo "error: $1"
  violations=$((violations + 1))
}

ALLOWLIST=(
  "scripts/college-xcodebuild-test.sh"
  "scripts/xcodebuild-test-parallel-flags.sh"
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

rg -n 'xcodebuild\b' "$ROOT/scripts" "$ROOT/.github/workflows" --glob '*.{sh,yml}' > "$TMP" 2>/dev/null || true

while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  file="${line%%:*}"
  rel="${file#"$ROOT/"}"
  content="${line#*:}"

  if [[ "$rel" == "scripts/audit-xcodebuild-test-parallelism.sh" ]]; then
    continue
  fi
  if [[ "$rel" == "scripts/copy-assistant-fixture-exports.sh" ]]; then
    continue
  fi
  if [[ "$content" == *"name:"* ]]; then
    continue
  fi
  trimmed="${content#"${content%%[![:space:]]*}"}"
  if [[ "$trimmed" == \#* ]]; then
    continue
  fi
  if [[ "$content" == *"echo "* ]]; then
    continue
  fi
  if [[ "$content" != *"xcodebuild "* && "$content" != *"college-xcodebuild-test.sh"* ]]; then
    continue
  fi
  if [[ "$content" != *" test"* && "$content" != *"test-without-building"* ]]; then
    continue
  fi
  if [[ "$content" == *"college-xcodebuild-test.sh"* ]]; then
    continue
  fi
  if is_allowlisted "$rel"; then
    continue
  fi
  if [[ "$content" == *"-maximum-parallel-testing-workers 2"* ]] \
    || [[ "$content" == *"-maximum-parallel-testing-workers"*"2"* ]]; then
    continue
  fi
  if [[ "$content" == *'${XCODEBUILD_TEST_PARALLEL_ARGS[@]}'* ]]; then
    continue
  fi
  fail "xcodebuild test missing -maximum-parallel-testing-workers 2 — $rel:$content"
done < "$TMP"

echo "xcodebuild test parallelism audit: $violations violation(s)"
if [[ "$violations" -gt 0 ]]; then
  exit 1
fi
