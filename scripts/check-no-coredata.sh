#!/usr/bin/env bash
# CI guard: Core Data removed after SwiftData migration Phase 7f.
# Use --report (or COREDATA_REPORT_ONLY=1) to print progress without failing.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_SRC="$ROOT/College"
TESTS_SRC="$ROOT/CollegeTests"
PATTERN='import CoreData|NSPersistentContainer|NSManagedObject|NSFetchRequest|@NSManaged'

REPORT_ONLY=0
if [[ "${1:-}" == "--report" ]] || [[ "${COREDATA_REPORT_ONLY:-}" == "1" ]]; then
  REPORT_ONLY=1
fi

count_matches() {
  { grep -rE "$PATTERN" "$APP_SRC" "$TESTS_SRC" 2>/dev/null || true; } | wc -l | tr -d ' '
}

count_files() {
  { grep -rlE "$PATTERN" "$APP_SRC" "$TESTS_SRC" 2>/dev/null || true; } | wc -l | tr -d ' '
}

count_import_files() {
  { grep -rl 'import CoreData' "$APP_SRC" "$TESTS_SRC" 2>/dev/null || true; } | wc -l | tr -d ' '
}

MATCH_LINES="$(count_matches)"
MATCH_FILES="$(count_files)"
IMPORT_FILES="$(count_import_files)"
COREDATA_DIR_FILES=0
if [[ -d "$APP_SRC/CoreData" ]]; then
  COREDATA_DIR_FILES="$(find "$APP_SRC/CoreData" -name '*.swift' 2>/dev/null | wc -l | tr -d ' ')"
fi

echo "Phase 7f Core Data progress:"
echo "  symbol match lines:  $MATCH_LINES"
echo "  files with symbols:  $MATCH_FILES"
echo "  files importing CD:  $IMPORT_FILES"
echo "  CoreData/*.swift:    $COREDATA_DIR_FILES"
echo "  xcdatamodeld:        $([ -d "$APP_SRC/CollegeDataModel.xcdatamodeld" ] && echo present || echo absent)"

if [[ "$REPORT_ONLY" -eq 1 ]]; then
  echo "note: report-only mode — gate not enforced until Phase 7f complete"
  exit 0
fi

if grep -rE "$PATTERN" "$APP_SRC" "$TESTS_SRC" 2>/dev/null; then
  echo "error: Core Data symbols still present (complete Phase 7f to pass)"
  exit 1
fi

echo "ok: no Core Data symbols in College app/tests sources"
