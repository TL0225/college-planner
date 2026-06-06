#!/usr/bin/env bash
# Weekly toolbar architecture health report (warn-only thresholds).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPORT="${REPORT:-$ROOT/toolbar-health-report.json}"
TOOLBAR_DIR="$ROOT/College/App/Toolbar"

toolbar_action_cases=$(grep -c "case " "$ROOT/College/App/Toolbar/ToolbarAction.swift" || true)
store_properties=$(grep -Ec "var |let " "$ROOT/College/App/Toolbar/AppToolbarStore.swift" || true)
toolbar_swift_files=$(find "$TOOLBAR_DIR" -name '*.swift' | wc -l | tr -d ' ')

warnings=()
if (( toolbar_action_cases > 40 )); then
  warnings+=("ToolbarAction cases ($toolbar_action_cases) > 40 — consider ADR 003 registry")
fi
if (( store_properties > 12 )); then
  warnings+=("AppToolbarStore properties ($store_properties) > 12 — review cross-tab creep")
fi
if (( toolbar_swift_files > 25 )); then
  warnings+=("Toolbar Swift files ($toolbar_swift_files) > 25 — consider feature module split")
fi

mkdir -p "$(dirname "$REPORT")"
{
  printf '{\n'
  printf '  "generatedAt": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '  "metrics": {\n'
  printf '    "toolbarActionCases": %s,\n' "$toolbar_action_cases"
  printf '    "appToolbarStoreProperties": %s,\n' "$store_properties"
  printf '    "toolbarSwiftFiles": %s\n' "$toolbar_swift_files"
  printf '  },\n'
  printf '  "warnings": [\n'
  if ((${#warnings[@]} > 0)); then
    for i in "${!warnings[@]}"; do
      comma=","
      [[ $i -eq $((${#warnings[@]} - 1)) ]] && comma=""
      printf '    "%s"%s\n' "${warnings[$i]//\"/\\\"}" "$comma"
    done
  fi
  printf '  ]\n'
  printf '}\n'
} > "$REPORT"

if ((${#warnings[@]} > 0)); then
  echo "toolbar-health-check: ${#warnings[@]} warning(s)"
  printf ' - %s\n' "${warnings[@]}"
else
  echo "toolbar-health-check: all metrics within thresholds"
fi

exit 0
