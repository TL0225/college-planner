#!/usr/bin/env bash
# CI guard: XCTSkip count in CollegeTests must not exceed docs/skipped-tests-registry.txt baseline.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REGISTRY="$ROOT/docs/skipped-tests-registry.txt"
TESTS="$ROOT/CollegeTests"

if [[ ! -f "$REGISTRY" ]]; then
  echo "error: missing skipped-test registry at docs/skipped-tests-registry.txt"
  exit 1
fi

baseline="$(grep -E '^baseline_count=' "$REGISTRY" | tail -1 | cut -d= -f2 | tr -d ' ')"
if [[ -z "$baseline" ]] || ! [[ "$baseline" =~ ^[0-9]+$ ]]; then
  echo "error: docs/skipped-tests-registry.txt must define baseline_count=<integer>"
  exit 1
fi

# Prefer ripgrep when present; fall back to grep for runners without rg (exit 127).
count_skips() {
  if command -v rg >/dev/null 2>&1; then
    rg -n 'XCTSkip|XCTSkipUnless' "$TESTS" --glob '*.swift' 2>/dev/null || true
  else
    grep -RInE 'XCTSkip|XCTSkipUnless' "$TESTS" --include='*.swift' 2>/dev/null || true
  fi
}

current="$(count_skips | wc -l | tr -d ' ')"

echo "skipped-test gate:"
echo "  baseline (registry): $baseline"
echo "  current (CollegeTests): $current"

if [[ "$current" -gt "$baseline" ]]; then
  echo "error: XCTSkip count grew without updating docs/skipped-tests-registry.txt"
  echo "hint: document the waiver, then bump baseline_count"
  count_skips || true
  exit 1
fi

if [[ "$current" -lt "$baseline" ]]; then
  echo "note: skip count dropped — consider lowering baseline_count in the registry"
fi

echo "ok: skipped-test count within baseline"
