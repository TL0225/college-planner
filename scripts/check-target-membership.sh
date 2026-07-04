#!/usr/bin/env bash
# CI guard: Career reorg must not leave flat + subfolder duplicates in the synced compile root.
# Xcode PBXFileSystemSynchronizedRootGroup compiles every Swift file under College/, so duplicate
# basenames are compile errors or stale move leftovers.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CAREER="$ROOT/College/Features/Career"

if [[ ! -d "$CAREER" ]]; then
  echo "check-target-membership: Career folder missing — skipping"
  exit 0
fi

# Files moved into subfolders during Career reorg; flat copies must not remain.
FORBIDDEN_FLAT=(
  CareerAIService.swift
  WorkdayScraper.swift
  CareerResumeLibrary.swift
  CareerStatsView.swift
  JobInspectorSidebar.swift
  JobBoardScraper.swift
)

violations=0

for base in "${FORBIDDEN_FLAT[@]}"; do
  flat="$CAREER/$base"
  if [[ -f "$flat" ]]; then
    echo "error: stale flat Career file still present: College/Features/Career/$base"
    violations=$((violations + 1))
  fi
done

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

find "$CAREER" -name '*.swift' -type f | sort | while IFS= read -r file; do
  base="$(basename "$file")"
  rel="${file#"$ROOT/"}"
  printf '%s\t%s\n' "$base" "$rel"
done > "$TMP"

while IFS= read -r base; do
  [[ -n "$base" ]] || continue
  echo "error: duplicate Career basename '$base':"
  grep -F "$base"$'\t' "$TMP" | cut -f2 | sed 's/^/  /'
  violations=$((violations + 1))
done < <(cut -f1 "$TMP" | sort | uniq -d)

if [[ "$violations" -gt 0 ]]; then
  echo "error: $violations Career target-membership violation(s)"
  exit 1
fi

echo "ok: no Career flat/subfolder duplicates under College/Features/Career"
