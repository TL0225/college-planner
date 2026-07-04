#!/usr/bin/env bash
# CI guard: perf manifest + baselines files exist and are well-formed.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT/docs/perf-optimization-manifest.tsv"
BASELINES="$ROOT/docs/perf-baselines.tsv"

[[ -f "$MANIFEST" ]] || { echo "error: missing $MANIFEST"; exit 1; }
[[ -f "$BASELINES" ]] || { echo "error: missing $BASELINES"; exit 1; }

manifest_rows=$(($(wc -l < "$MANIFEST") - 1))
baseline_rows=$(($(wc -l < "$BASELINES") - 1))

if [[ "$manifest_rows" -lt 1 ]]; then
  echo "error: perf-optimization-manifest.tsv is empty"
  exit 1
fi

if [[ "$baseline_rows" -lt 7 ]]; then
  echo "error: perf-baselines.tsv must list at least 7 scenarios (found $baseline_rows)"
  exit 1
fi

echo "check-perf-manifest: ok ($manifest_rows manifest rows, $baseline_rows baseline scenarios)"
