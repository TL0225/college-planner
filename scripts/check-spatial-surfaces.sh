#!/usr/bin/env bash
# M30-050 — Part 28.9 spatial acceptance gate (forbidden overlay patterns).
set -euo pipefail
cd "$(dirname "$0")/.."

SCAN_DIRS=(College Packages/CollegeCalendar/Sources Packages/CollegeAcademics/Sources Packages/CollegeCareer/Sources)
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

violations=0

record_violation() {
  echo "error: $1"
  violations=$((violations + 1))
}

# Legacy full-screen calendar modal host must not return.
if rg -n "CalendarModalHost" College Packages --glob '*.swift' >/dev/null 2>&1; then
  record_violation "CalendarModalHost still referenced"
fi

# No floatingCards presentation style in active calendar editor paths.
if rg -n '\.floatingCards|case floatingCards' College/Features/Calendar --glob '*.swift' 2>/dev/null | tee -a "$TMP"; then
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    record_violation "floatingCards spatial tier — $line"
  done < "$TMP"
  : >"$TMP"
fi

# ContentView must not host zIndex 100 profile/course overlays.
if rg -n 'zIndex\(100\)' College/App/ContentView.swift 2>/dev/null | tee -a "$TMP"; then
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    record_violation "ContentView zIndex overlay — $line"
  done < "$TMP"
  : >"$TMP"
fi

# Calendar event detail must use inspector, not detached sheet.
if rg -n '\.sheet\(item: \$eventDetailSelection' Packages/CollegeCalendar --glob '*.swift' 2>/dev/null; then
  record_violation "calendar event detail still uses sheet instead of inspector"
fi

# WKWebView process recovery must be wired on primary coordinators.
for file in \
  College/Features/LMS/LMSWebCoordinator.swift \
  College/Features/Career/Apply/CareerApplyCoordinator.swift \
  College/Core/WebShortcuts/ShortcutWebCoordinator.swift; do
  if ! rg -q 'webViewWebContentProcessDidTerminate' "$file"; then
    record_violation "missing webViewWebContentProcessDidTerminate in $file"
  fi
done

echo "spatial-surfaces gate: $violations violation(s)"
if [[ "$violations" -gt 0 ]]; then
  exit 1
fi
echo "ok: spatial surfaces PASS"
