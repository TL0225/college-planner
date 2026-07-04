#!/usr/bin/env bash
# CI guard: technology-neutral persistence naming (Phase 0+ reorg).
# Fails on banned Core Data / SwiftData labels in app sources and active docs.
# Use --report (or NEUTRAL_PERSISTENCE_REPORT_ONLY=1) to print counts without failing.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

REPORT_ONLY=0
if [[ "${1:-}" == "--report" ]] || [[ "${NEUTRAL_PERSISTENCE_REPORT_ONLY:-}" == "1" ]]; then
  REPORT_ONLY=1
fi

COREDATA_RE='CoreData|Core Data|CoreDataManager|coreData'
SWIFTDATA_RE='SwiftData|Swift Data|swiftData'
LEGACY_API_RE='syncFromCoreData|purge.*FromCoreData|NSManaged|NSPersistent|xcdatamodel'
COMBINED_RE="${COREDATA_RE}|${SWIFTDATA_RE}|${LEGACY_API_RE}"

SCAN_DIRS=(
  "$ROOT/College"
  "$ROOT/CollegeTests"
  "$ROOT/CollegeUITests"
)

TMP_VIOLATIONS="$(mktemp)"
trap 'rm -f "$TMP_VIOLATIONS"' EXIT

collect_files() {
  local dir
  for dir in "${SCAN_DIRS[@]}"; do
    [[ -d "$dir" ]] || continue
    if [[ "$dir" == "$ROOT/docs" ]]; then
      find "$dir" -type f \( -name '*.swift' -o -name '*.md' -o -name '*.sh' -o -name '*.txt' -o -name '*.xcstrings' \) \
        ! -path "$ROOT/docs/archive/*" 2>/dev/null || true
    else
      find "$dir" -type f \( -name '*.swift' -o -name '*.md' -o -name '*.sh' -o -name '*.txt' -o -name '*.xcstrings' \) 2>/dev/null || true
    fi
  done | sort -u
}

while IFS= read -r file; do
  [[ -n "$file" ]] || continue
  # Implementation storage layer and ADRs may name the framework explicitly.
  case "$file" in
    */College/Core/Data/Storage/*|*/College/Core/Data/Repositories/*|*/docs/adr/*)
      continue
      ;;
  esac
  while IFS= read -r match; do
    [[ -n "$match" ]] || continue
    line_no="${match%%:*}"
    content="${match#*:}"
    if [[ "$content" =~ ^[[:space:]]*import[[:space:]]+SwiftData[[:space:]]*$ ]]; then
      continue
    fi
    # Framework type / API identifiers required by the compiler.
    if [[ "$content" =~ SwiftDataError|ModelContainer|ModelContext|ModelConfiguration ]]; then
      continue
    fi
    printf '%s\n' "${file}:${line_no}:${content}" >> "$TMP_VIOLATIONS"
  done < <(grep -Eni "$COMBINED_RE" "$file" 2>/dev/null || true)
done < <(collect_files)

VIOLATION_LINES=0
VIOLATION_FILES=0
COREDATA_LINES=0
SWIFTDATA_LINES=0
LEGACY_LINES=0

if [[ -s "$TMP_VIOLATIONS" ]]; then
  VIOLATION_LINES="$(wc -l < "$TMP_VIOLATIONS" | tr -d ' ')"
  VIOLATION_FILES="$(cut -d: -f1 "$TMP_VIOLATIONS" | sort -u | wc -l | tr -d ' ')"
  COREDATA_LINES="$(grep -Eci "$COREDATA_RE" "$TMP_VIOLATIONS" 2>/dev/null || true)"
  SWIFTDATA_LINES="$(grep -Eci "$SWIFTDATA_RE" "$TMP_VIOLATIONS" 2>/dev/null || true)"
  LEGACY_LINES="$(grep -Eci "$LEGACY_API_RE" "$TMP_VIOLATIONS" 2>/dev/null || true)"
fi

XCDATAMODEL_STATUS="absent"
if [[ -d "$ROOT/College/CollegeDataModel.xcdatamodeld" ]]; then
  XCDATAMODEL_STATUS="present"
fi

echo "Neutral persistence label gate:"
echo "  violation lines:       $VIOLATION_LINES"
echo "  files with hits:       $VIOLATION_FILES"
echo "  coredata-label lines:  $COREDATA_LINES"
echo "  swiftdata-label lines: $SWIFTDATA_LINES"
echo "  legacy-api lines:      $LEGACY_LINES"
echo "  xcdatamodeld:          $XCDATAMODEL_STATUS"

if [[ "$REPORT_ONLY" -eq 1 ]]; then
  echo "note: report-only mode — gate not enforced until legacy labels removed"
  exit 0
fi

if [[ "$VIOLATION_LINES" -gt 0 ]]; then
  echo "error: banned persistence labels found (run with --report for summary):"
  head -50 "$TMP_VIOLATIONS"
  if [[ "$VIOLATION_LINES" -gt 50 ]]; then
    echo "... ($((VIOLATION_LINES - 50)) more)"
  fi
  exit 1
fi

echo "ok: no banned persistence labels in scanned sources"
